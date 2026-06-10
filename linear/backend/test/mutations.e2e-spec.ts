import { randomUUID } from 'node:crypto';
import { INestApplication } from '@nestjs/common';
import type { MutationCommand, MutationResponse } from '@linear/shared';
import { isValidOrderKey } from '@linear/shared';
import { PrismaClient } from '@prisma/client';
import request from 'supertest';
import { App } from 'supertest/types';
import { createTestApp, resetDb, signupActor, TestActor } from './helpers';

describe('mutations (e2e)', () => {
  let app: INestApplication<App>;
  let alice: TestActor;
  let teamId: number;
  let stateIds: number[];
  const prisma = new PrismaClient();

  const mutate = (
    actor: TestActor,
    command: MutationCommand,
    override: Partial<{ clientMutationId: string; workspaceId: number }> = {},
  ) =>
    request(app.getHttpServer())
      .post('/mutations')
      .set('Authorization', `Bearer ${actor.token}`)
      .send({
        clientMutationId: override.clientMutationId ?? randomUUID(),
        workspaceId: override.workspaceId ?? actor.workspaceId,
        command,
      });

  beforeAll(async () => {
    app = await createTestApp();
  });

  beforeEach(async () => {
    await resetDb(prisma);
    alice = await signupActor(app, 'alice@example.com', 'Alice');
    const team = await prisma.team.findFirstOrThrow({
      where: { workspaceId: alice.workspaceId },
      include: { states: { orderBy: { position: 'asc' } } },
    });
    teamId = team.id;
    stateIds = team.states.map((s) => s.id);
  });

  afterAll(async () => {
    await app.close();
    await prisma.$disconnect();
  });

  it('createIssue: number 採番 / 既定 state / sortOrder 生成 / sync_ops 追記', async () => {
    const res = await mutate(alice, {
      type: 'createIssue',
      teamId,
      title: 'First issue',
    }).expect(200);

    const body = res.body as MutationResponse;
    expect(body.ops).toHaveLength(1);
    expect(body.lastSyncId).toBe(1);
    const op = body.ops[0];
    expect(op.seq).toBe(1);
    expect(op.entityType).toBe('issue');
    expect(op.action).toBe('insert');
    const payload = op.payload as {
      number: number;
      stateId: number;
      sortOrder: string;
    };
    expect(payload.number).toBe(1);
    expect(payload.stateId).toBe(stateIds[0]); // 先頭 = Backlog
    expect(isValidOrderKey(payload.sortOrder)).toBe(true);

    expect(await prisma.issue.count({ where: { teamId } })).toBe(1);
    expect(
      await prisma.mutationLedger.count({
        where: { workspaceId: alice.workspaceId },
      }),
    ).toBe(1);
  });

  it('連続する mutation の seq は gap なく増える / number も連番', async () => {
    const r1 = (await mutate(alice, {
      type: 'createIssue',
      teamId,
      title: 'A',
    }).expect(200)) as { body: MutationResponse };
    const r2 = (await mutate(alice, {
      type: 'createIssue',
      teamId,
      title: 'B',
    }).expect(200)) as { body: MutationResponse };

    expect(r1.body.ops[0].seq).toBe(1);
    expect(r2.body.ops[0].seq).toBe(2);
    expect((r2.body.ops[0].payload as { number: number }).number).toBe(2);

    const seqs = (
      await prisma.syncOp.findMany({
        where: { workspaceId: alice.workspaceId },
        orderBy: { seq: 'asc' },
      })
    ).map((o) => Number(o.seq));
    expect(seqs).toEqual([1, 2]);
  });

  it('同じ clientMutationId の再送は冪等 (記録済み ops を返し、副作用なし)', async () => {
    const cmid = randomUUID();
    const first = (await mutate(
      alice,
      { type: 'createIssue', teamId, title: 'Once' },
      { clientMutationId: cmid },
    ).expect(200)) as { body: MutationResponse };

    const replay = (await mutate(
      alice,
      { type: 'createIssue', teamId, title: 'Once' },
      { clientMutationId: cmid },
    ).expect(200)) as { body: MutationResponse };

    expect(replay.body).toEqual(first.body);
    expect(await prisma.issue.count({ where: { teamId } })).toBe(1);
    expect(
      await prisma.syncOp.count({ where: { workspaceId: alice.workspaceId } }),
    ).toBe(1);
  });

  it('createIssue + labelIds は issue + issue_label の連続 ops になる', async () => {
    const label = (await mutate(alice, {
      type: 'createLabel',
      teamId,
      name: 'bug',
      color: '#ff0000',
    }).expect(200)) as { body: MutationResponse };
    const labelId = (label.body.ops[0].payload as { id: number }).id;

    const res = (await mutate(alice, {
      type: 'createIssue',
      teamId,
      title: 'With label',
      labelIds: [labelId],
    }).expect(200)) as { body: MutationResponse };

    expect(res.body.ops.map((o) => o.entityType)).toEqual([
      'issue',
      'issue_label',
    ]);
    expect(res.body.ops.map((o) => o.seq)).toEqual([2, 3]);
  });

  it('moveIssue: stateId + sortOrder の partial update op', async () => {
    const created = (await mutate(alice, {
      type: 'createIssue',
      teamId,
      title: 'Move me',
    }).expect(200)) as { body: MutationResponse };
    const issueId = created.body.ops[0].entityId;

    const res = (await mutate(alice, {
      type: 'moveIssue',
      issueId,
      stateId: stateIds[2],
      sortOrder: 'V',
    }).expect(200)) as { body: MutationResponse };

    expect(res.body.ops[0].action).toBe('update');
    expect(res.body.ops[0].payload).toMatchObject({
      stateId: stateIds[2],
      sortOrder: 'V',
    });
    const issue = await prisma.issue.findUniqueOrThrow({
      where: { id: issueId },
    });
    expect(issue.stateId).toBe(stateIds[2]);
  });

  it('deleteIssue: comments もカスケードで消え、op は issue delete 1 件', async () => {
    const created = (await mutate(alice, {
      type: 'createIssue',
      teamId,
      title: 'Doomed',
    }).expect(200)) as { body: MutationResponse };
    const issueId = created.body.ops[0].entityId;
    await mutate(alice, {
      type: 'createComment',
      issueId,
      body: 'soon to be gone',
    }).expect(200);

    const res = (await mutate(alice, {
      type: 'deleteIssue',
      issueId,
    }).expect(200)) as { body: MutationResponse };

    expect(res.body.ops).toHaveLength(1);
    expect(res.body.ops[0]).toMatchObject({
      entityType: 'issue',
      action: 'delete',
    });
    expect(await prisma.issue.count({ where: { id: issueId } })).toBe(0);
    expect(await prisma.comment.count({ where: { issueId } })).toBe(0);
  });

  it('createTeam: team + 既定 5 states の 6 ops / key 重複は 409', async () => {
    const res = (await mutate(alice, {
      type: 'createTeam',
      key: 'ENG',
      name: 'Engineering',
    }).expect(200)) as { body: MutationResponse };
    expect(res.body.ops).toHaveLength(6);
    expect(res.body.ops[0].entityType).toBe('team');
    expect(
      res.body.ops.slice(1).every((o) => o.entityType === 'workflow_state'),
    ).toBe(true);

    await mutate(alice, {
      type: 'createTeam',
      key: 'ENG',
      name: 'Engineering again',
    }).expect(409);
  });

  it('他 workspace のメンバーでなければ 403', async () => {
    const mallory = await signupActor(app, 'mallory@example.com', 'Mallory');
    await mutate(
      mallory,
      { type: 'createIssue', teamId, title: 'Hi' },
      {
        workspaceId: alice.workspaceId,
      },
    ).expect(403);
  });

  it('認証なしは 401 / 空 patch は 400 / 不正 UUID は 400', async () => {
    await request(app.getHttpServer()).post('/mutations').send({}).expect(401);

    await mutate(alice, {
      type: 'updateIssue',
      issueId: 1,
      patch: {},
    } as unknown as MutationCommand).expect(400);

    await mutate(
      alice,
      { type: 'deleteIssue', issueId: 1 },
      { clientMutationId: 'not-a-uuid' },
    ).expect(400);
  });

  it('他 team の state への moveIssue は 422', async () => {
    const created = (await mutate(alice, {
      type: 'createIssue',
      teamId,
      title: 'Stay',
    }).expect(200)) as { body: MutationResponse };
    const issueId = created.body.ops[0].entityId;

    const other = (await mutate(alice, {
      type: 'createTeam',
      key: 'OPS',
      name: 'Operations',
    }).expect(200)) as { body: MutationResponse };
    const foreignStateId = other.body.ops[1].entityId;

    await mutate(alice, {
      type: 'moveIssue',
      issueId,
      stateId: foreignStateId,
      sortOrder: 'V',
    }).expect(422);
  });
});
