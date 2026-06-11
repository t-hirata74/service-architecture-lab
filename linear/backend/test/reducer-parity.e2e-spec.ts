import { randomUUID } from 'node:crypto';
import { INestApplication } from '@nestjs/common';
import {
  applyOp,
  BootstrapResponseSchema,
  fromBootstrap,
} from '@linear/shared';
import type {
  MutationCommand,
  MutationResponse,
  SyncOp,
  WorkspaceSnapshot,
} from '@linear/shared';
import { PrismaClient } from '@prisma/client';
import request from 'supertest';
import { App } from 'supertest/types';
import { createTestApp, resetDb, signupActor, TestActor } from './helpers';

/**
 * ADR 0004 の「FE reducer と BE 適用の意味一致 (parity)」を固定するテスト。
 *
 *   fromBootstrap(bootstrap@0) に全 ops を applyOp で畳み込んだ結果
 *     ≡ 最終 bootstrap (server の materialized state)
 *
 * これが成立する限り、client の confirmed state は server とドリフトしない。
 */
describe('shared reducer ⇔ backend parity (e2e)', () => {
  let app: INestApplication<App>;
  let alice: TestActor;
  const prisma = new PrismaClient();

  const mutate = async (
    command: MutationCommand,
  ): Promise<MutationResponse> => {
    const res = await request(app.getHttpServer())
      .post('/mutations')
      .set('Authorization', `Bearer ${alice.token}`)
      .send({
        clientMutationId: randomUUID(),
        workspaceId: alice.workspaceId,
        command,
      })
      .expect(200);
    return res.body as MutationResponse;
  };

  const bootstrap = async () => {
    const res = await request(app.getHttpServer())
      .get(`/sync/bootstrap?workspaceId=${alice.workspaceId}`)
      .set('Authorization', `Bearer ${alice.token}`)
      .expect(200);
    return BootstrapResponseSchema.parse(res.body);
  };

  /** 配列の並びだけ正規化して比較する (ops 挿入順 vs bootstrap ORDER BY) */
  const canonical = (snap: WorkspaceSnapshot): WorkspaceSnapshot => ({
    ...snap,
    issueLabels: [...snap.issueLabels].sort(
      (a, b) => a.issueId - b.issueId || a.labelId - b.labelId,
    ),
    members: [...snap.members].sort((a, b) => a.userId - b.userId),
  });

  beforeAll(async () => {
    app = await createTestApp();
  });

  beforeEach(async () => {
    await resetDb(prisma);
    alice = await signupActor(app, 'alice@example.com', 'Alice');
  });

  afterAll(async () => {
    await app.close();
    await prisma.$disconnect();
  });

  it('bootstrap(0) + 全 ops の畳み込み ≡ 最終 bootstrap', async () => {
    const b0 = await bootstrap();
    expect(b0.lastSyncId).toBe(0);
    const genTeam = b0.teams[0];

    const ops: SyncOp[] = [];
    const collect = (r: MutationResponse) => ops.push(...r.ops);

    // 全コマンド種を踏む一連の操作
    const team = await mutate({
      type: 'createTeam',
      key: 'ENG',
      name: 'Engineering',
    });
    collect(team);
    const engTeamId = team.ops[0].entityId;

    const label = await mutate({
      type: 'createLabel',
      teamId: genTeam.id,
      name: 'bug',
      color: '#ff0000',
    });
    collect(label);
    const labelId = label.ops[0].entityId;

    const issueA = await mutate({
      type: 'createIssue',
      teamId: genTeam.id,
      title: 'Issue A',
      description: 'first',
      labelIds: [labelId],
    });
    collect(issueA);
    const issueAId = issueA.ops[0].entityId;

    const issueB = await mutate({
      type: 'createIssue',
      teamId: engTeamId,
      title: 'Issue B',
      priority: 2,
    });
    collect(issueB);
    const issueBId = issueB.ops[0].entityId;

    collect(
      await mutate({
        type: 'updateIssue',
        issueId: issueAId,
        patch: { title: 'Issue A (renamed)', priority: 1, description: null },
      }),
    );

    const engStates = await prisma.workflowState.findMany({
      where: { teamId: engTeamId },
      orderBy: { position: 'asc' },
    });
    collect(
      await mutate({
        type: 'moveIssue',
        issueId: issueBId,
        stateId: engStates[2].id,
        sortOrder: 'G',
      }),
    );

    collect(
      await mutate({ type: 'createComment', issueId: issueAId, body: 'note' }),
    );
    collect(
      await mutate({ type: 'removeIssueLabel', issueId: issueAId, labelId }),
    );
    collect(
      await mutate({ type: 'addIssueLabel', issueId: issueAId, labelId }),
    );
    collect(await mutate({ type: 'deleteIssue', issueId: issueBId }));

    // E1 (ADR 0006): membership の insert / delete も reducer と一致すること。
    // mallory は remove され、users からも落ちる (membership 従属) のが parity の要
    await signupActor(app, 'bob@example.com', 'Bob');
    const mallory = await signupActor(app, 'mallory@example.com', 'Mallory');
    collect(
      await mutate({
        type: 'inviteMember',
        email: 'bob@example.com',
        role: 'member',
      }),
    );
    collect(
      await mutate({
        type: 'inviteMember',
        email: 'mallory@example.com',
        role: 'admin',
      }),
    );
    collect(await mutate({ type: 'removeMember', userId: mallory.userId }));

    // seq 連続の確認 (前提条件)
    expect(ops.map((o) => o.seq)).toEqual(ops.map((_, i) => i + 1));

    const replayed = ops.reduce(applyOp, fromBootstrap(b0));
    const final = await bootstrap();
    expect(final.lastSyncId).toBe(ops.length);

    expect(canonical(replayed)).toEqual(canonical(fromBootstrap(final)));
  });
});
