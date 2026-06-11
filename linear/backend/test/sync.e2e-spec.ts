import { randomUUID } from 'node:crypto';
import { INestApplication } from '@nestjs/common';
import type { DeltaResponse, MutationCommand } from '@linear/shared';
import { BootstrapResponseSchema } from '@linear/shared';
import { PrismaClient } from '@prisma/client';
import request from 'supertest';
import { App } from 'supertest/types';
import { createTestApp, resetDb, signupActor, TestActor } from './helpers';

describe('sync bootstrap/delta (e2e)', () => {
  let app: INestApplication<App>;
  let alice: TestActor;
  let teamId: number;
  const prisma = new PrismaClient();

  const mutate = (actor: TestActor, command: MutationCommand) =>
    request(app.getHttpServer())
      .post('/mutations')
      .set('Authorization', `Bearer ${actor.token}`)
      .send({
        clientMutationId: randomUUID(),
        workspaceId: actor.workspaceId,
        command,
      })
      .expect(200);

  const get = (actor: TestActor, path: string) =>
    request(app.getHttpServer())
      .get(path)
      .set('Authorization', `Bearer ${actor.token}`);

  beforeAll(async () => {
    app = await createTestApp();
  });

  beforeEach(async () => {
    await resetDb(prisma);
    alice = await signupActor(app, 'alice@example.com', 'Alice');
    const team = await prisma.team.findFirstOrThrow({
      where: { workspaceId: alice.workspaceId },
    });
    teamId = team.id;

    // seq 1..5: issue ×2 / label / addIssueLabel / comment
    await mutate(alice, { type: 'createIssue', teamId, title: 'Issue A' });
    await mutate(alice, { type: 'createIssue', teamId, title: 'Issue B' });
    await mutate(alice, {
      type: 'createLabel',
      teamId,
      name: 'bug',
      color: '#ff0000',
    });
    const issue = await prisma.issue.findFirstOrThrow({
      where: { teamId, title: 'Issue A' },
    });
    const label = await prisma.label.findFirstOrThrow({ where: { teamId } });
    await mutate(alice, {
      type: 'addIssueLabel',
      issueId: issue.id,
      labelId: label.id,
    });
    await mutate(alice, {
      type: 'createComment',
      issueId: issue.id,
      body: 'first!',
    });
  });

  afterAll(async () => {
    await app.close();
    await prisma.$disconnect();
  });

  it('bootstrap: shared スキーマに適合する snapshot + lastSyncId を返す', async () => {
    const res = await get(
      alice,
      `/sync/bootstrap?workspaceId=${alice.workspaceId}`,
    ).expect(200);

    // FE/BE コントラクトそのものを zod で検証する (ADR 0004)
    const body = BootstrapResponseSchema.parse(res.body);
    expect(body.lastSyncId).toBe(5);
    expect(body.workspace.id).toBe(alice.workspaceId);
    expect(body.users).toHaveLength(1);
    expect(body.members).toHaveLength(1);
    expect(body.teams).toHaveLength(1);
    expect(body.states).toHaveLength(5);
    expect(body.issues).toHaveLength(2);
    expect(body.labels).toHaveLength(1);
    expect(body.issueLabels).toHaveLength(1);
    expect(body.comments).toHaveLength(1);
  });

  it('delta: since より後の op を seq 順で返す', async () => {
    const all = (await get(
      alice,
      `/sync/delta?workspaceId=${alice.workspaceId}&since=0`,
    ).expect(200)) as { body: DeltaResponse };
    expect(all.body.ops.map((o) => o.seq)).toEqual([1, 2, 3, 4, 5]);
    expect(all.body.lastSyncId).toBe(5);

    const tail = (await get(
      alice,
      `/sync/delta?workspaceId=${alice.workspaceId}&since=3`,
    ).expect(200)) as { body: DeltaResponse };
    expect(tail.body.ops.map((o) => o.seq)).toEqual([4, 5]);

    const empty = (await get(
      alice,
      `/sync/delta?workspaceId=${alice.workspaceId}&since=5`,
    ).expect(200)) as { body: DeltaResponse };
    expect(empty.body.ops).toEqual([]);
    expect(empty.body.lastSyncId).toBe(5);
  });

  it('activity: issue の変更履歴を sync_ops の projection として返す', async () => {
    const issue = await prisma.issue.findFirstOrThrow({
      where: { teamId, title: 'Issue A' },
    });
    const res = await get(
      alice,
      `/sync/activity?workspaceId=${alice.workspaceId}&issueId=${issue.id}`,
    ).expect(200);
    const body = res.body as { ops: Array<{ seq: number; action: string }> };
    // Issue A に対する op は insert (seq 1) のみ。新しい順
    expect(body.ops.map((o) => o.action)).toEqual(['insert']);

    const mallory = await signupActor(app, 'mallory2@example.com', 'Mallory');
    await get(
      mallory,
      `/sync/activity?workspaceId=${alice.workspaceId}&issueId=${issue.id}`,
    ).expect(403);
  });

  it('非メンバーの bootstrap / delta は 403', async () => {
    const mallory = await signupActor(app, 'mallory@example.com', 'Mallory');
    await get(
      mallory,
      `/sync/bootstrap?workspaceId=${alice.workspaceId}`,
    ).expect(403);
    await get(
      mallory,
      `/sync/delta?workspaceId=${alice.workspaceId}&since=0`,
    ).expect(403);
  });

  it('不正な query は 400 (zod coerce)', async () => {
    await get(alice, '/sync/bootstrap').expect(400);
    await get(alice, '/sync/bootstrap?workspaceId=abc').expect(400);
    await get(
      alice,
      `/sync/delta?workspaceId=${alice.workspaceId}&since=-1`,
    ).expect(400);
    await get(alice, `/sync/delta?workspaceId=${alice.workspaceId}`).expect(
      400,
    );
  });
});
