import { randomUUID } from 'node:crypto';
import { INestApplication } from '@nestjs/common';
import type { MutationCommand, MutationResponse } from '@linear/shared';
import { PrismaClient } from '@prisma/client';
import request from 'supertest';
import { App } from 'supertest/types';
import { createTestApp, resetDb, signupActor, TestActor } from './helpers';

/**
 * E1 (ADR 0006): メンバー招待 / 削除 = sync protocol の進化。
 * workspace_member が op の対象になり、role による認可 (admin 限定) が入る。
 */
describe('membership (e2e)', () => {
  let app: INestApplication<App>;
  let alice: TestActor;
  let bob: TestActor;
  let bobEmail: string;
  const prisma = new PrismaClient();

  const mutate = (
    actor: TestActor,
    command: MutationCommand,
    workspaceId?: number,
  ) =>
    request(app.getHttpServer())
      .post('/mutations')
      .set('Authorization', `Bearer ${actor.token}`)
      .send({
        clientMutationId: randomUUID(),
        workspaceId: workspaceId ?? actor.workspaceId,
        command,
      });

  const bootstrap = (actor: TestActor, workspaceId: number) =>
    request(app.getHttpServer())
      .get(`/sync/bootstrap?workspaceId=${workspaceId}`)
      .set('Authorization', `Bearer ${actor.token}`);

  beforeAll(async () => {
    app = await createTestApp();
  });

  beforeEach(async () => {
    await resetDb(prisma);
    alice = await signupActor(app, 'alice@example.com', 'Alice');
    bobEmail = 'bob@example.com';
    bob = await signupActor(app, bobEmail, 'Bob');
  });

  afterAll(async () => {
    await app.close();
    await prisma.$disconnect();
  });

  it('inviteMember: 登録済み email を member に加え、op に user 表示情報が同梱される', async () => {
    const res = await mutate(alice, {
      type: 'inviteMember',
      email: bobEmail,
      role: 'member',
    }).expect(200);
    const body = res.body as MutationResponse;
    expect(body.ops).toHaveLength(1);
    expect(body.ops[0]).toMatchObject({
      entityType: 'workspace_member',
      entityId: bob.userId,
      action: 'insert',
      payload: {
        userId: bob.userId,
        role: 'member',
        user: { id: bob.userId, name: 'Bob' },
      },
    });

    // bob は alice の workspace へアクセスできるようになる (bootstrap + mutation)
    const boot = await bootstrap(bob, alice.workspaceId).expect(200);
    const snapshot = boot.body as {
      members: unknown[];
      users: Array<{ id: number }>;
    };
    expect(snapshot.members).toHaveLength(2);
    const team = await prisma.team.findFirstOrThrow({
      where: { workspaceId: alice.workspaceId },
    });
    await mutate(
      bob,
      { type: 'createIssue', teamId: team.id, title: 'From Bob' },
      alice.workspaceId,
    ).expect(200);
  });

  it('admin 以外の招待は 403 / 未登録 email は 422 / 重複は 409', async () => {
    await mutate(alice, {
      type: 'inviteMember',
      email: bobEmail,
      role: 'member',
    }).expect(200);

    // bob は role=member なので招待できない
    await mutate(
      bob,
      { type: 'inviteMember', email: 'mallory@example.com', role: 'member' },
      alice.workspaceId,
    ).expect(403);

    await mutate(alice, {
      type: 'inviteMember',
      email: 'unknown@example.com',
      role: 'member',
    }).expect(422);

    await mutate(alice, {
      type: 'inviteMember',
      email: bobEmail,
      role: 'member',
    }).expect(409);
  });

  it('removeMember: 本人はアクセスを失う / 自分自身は 422 / member には 403', async () => {
    await mutate(alice, {
      type: 'inviteMember',
      email: bobEmail,
      role: 'member',
    }).expect(200);

    // member (bob) は remove できない
    await mutate(
      bob,
      { type: 'removeMember', userId: alice.userId },
      alice.workspaceId,
    ).expect(403);

    // 自分自身は remove できない
    await mutate(alice, {
      type: 'removeMember',
      userId: alice.userId,
    }).expect(422);

    const res = await mutate(alice, {
      type: 'removeMember',
      userId: bob.userId,
    }).expect(200);
    expect((res.body as MutationResponse).ops[0]).toMatchObject({
      entityType: 'workspace_member',
      action: 'delete',
      payload: { userId: bob.userId },
    });

    await bootstrap(bob, alice.workspaceId).expect(403);
  });
});
