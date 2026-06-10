import { randomUUID } from 'node:crypto';
import { INestApplication } from '@nestjs/common';
import type { DeltaResponse, MutationResponse } from '@linear/shared';
import { PrismaClient } from '@prisma/client';
import request from 'supertest';
import { App } from 'supertest/types';
import { createTestApp, resetDb, signupActor, TestActor } from './helpers';

/**
 * ADR 0002 の不変条件の実証テスト。
 *
 * 並行 mutation の最中に delta を読み続けても、観測される seq 列に
 * 「欠番」や「lastSyncId 以下の遅延出現」が無いこと。
 * counter 行 FOR UPDATE 採番 (commit 順 = seq 順) が壊れると、
 * AUTO_INCREMENT 採番と同様に reader が op を読み飛ばし、ここが落ちる。
 */
describe('sync log gapless invariant (e2e)', () => {
  let app: INestApplication<App>;
  let alice: TestActor;
  const prisma = new PrismaClient();

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

  it('並行 30 mutation 中の delta 読者が gap を観測しない', async () => {
    const server = app.getHttpServer();
    const auth = ['Authorization', `Bearer ${alice.token}`] as const;

    // 2 team 目を作って workspace ロック → team ロックの並行系も踏む (seq 1..6)
    const teamRes = await request(server)
      .post('/mutations')
      .set(...auth)
      .send({
        clientMutationId: randomUUID(),
        workspaceId: alice.workspaceId,
        command: { type: 'createTeam', key: 'ENG', name: 'Engineering' },
      })
      .expect(200);
    const baseSeq = (teamRes.body as MutationResponse).lastSyncId;
    expect(baseSeq).toBe(6);

    const teams = await prisma.team.findMany({
      where: { workspaceId: alice.workspaceId },
      orderBy: { id: 'asc' },
    });
    expect(teams).toHaveLength(2);

    const N = 30;
    const finalSeq = baseSeq + N; // createIssue は 1 op

    // writer: 2 team へ交互に並行発射 (採番はすべて workspace ロックで直列化される)
    const writers = Promise.all(
      Array.from({ length: N }, (_, i) =>
        request(server)
          .post('/mutations')
          .set(...auth)
          .send({
            clientMutationId: randomUUID(),
            workspaceId: alice.workspaceId,
            command: {
              type: 'createIssue',
              teamId: teams[i % 2].id,
              title: `concurrent-${i}`,
            },
          })
          .expect(200),
      ),
    );

    // reader: 書き込みと並行に delta をポーリングし、連続性をその場で検証する
    const observed: number[] = [];
    let last = baseSeq;
    const deadline = Date.now() + 25_000;
    while (last < finalSeq) {
      const res = await request(server)
        .get(`/sync/delta?workspaceId=${alice.workspaceId}&since=${last}`)
        .set(...auth)
        .expect(200);
      const body = res.body as DeltaResponse;
      for (const op of body.ops) {
        // 欠番があればここで即座に落ちる
        expect(op.seq).toBe(last + 1);
        last = op.seq;
        observed.push(op.seq);
      }
      // lastSyncId が進んでいるのに ops が空、は「採番済み未 commit を読み飛ばした」signal
      expect(body.lastSyncId).toBeLessThanOrEqual(finalSeq);
      if (Date.now() > deadline) {
        throw new Error(`timeout: observed up to seq=${last}`);
      }
      await new Promise((r) => setTimeout(r, 5));
    }

    await writers;

    // 全体整合: 観測列はちょうど baseSeq+1..finalSeq で重複なし
    expect(observed).toEqual(
      Array.from({ length: N }, (_, i) => baseSeq + 1 + i),
    );

    // per-team issue number も穴なし連番 (team counter FOR UPDATE / ADR 0002)
    for (const team of teams) {
      const numbers = (
        await prisma.issue.findMany({
          where: { teamId: team.id },
          select: { number: true },
          orderBy: { number: 'asc' },
        })
      ).map((i) => i.number);
      expect(numbers).toEqual(
        Array.from({ length: numbers.length }, (_, i) => i + 1),
      );
    }
    expect(
      await prisma.issue.count({
        where: { team: { workspaceId: alice.workspaceId } },
      }),
    ).toBe(N);
  }, 30_000);
});
