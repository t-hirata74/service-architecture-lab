import { createServer, Server } from 'node:http';
import { randomUUID } from 'node:crypto';
import { AddressInfo } from 'node:net';
import { INestApplication } from '@nestjs/common';
import type { MutationResponse, TriageResponse } from '@linear/shared';
import { PrismaClient } from '@prisma/client';
import request from 'supertest';
import { App } from 'supertest/types';
import { createTestApp, resetDb, signupActor, TestActor } from './helpers';

/** ai-worker を模す最小 HTTP サーバ (トークン検証 + 固定応答) */
function startMockWorker(): Promise<{
  server: Server;
  url: string;
  seenTokens: string[];
}> {
  const seenTokens: string[] = [];
  const server = createServer((req, res) => {
    seenTokens.push(String(req.headers['x-internal-token'] ?? ''));
    res.setHeader('Content-Type', 'application/json');
    if (req.url === '/triage') {
      res.end(JSON.stringify({ priority: 1, labels: ['bug'], reason: 'mock' }));
    } else if (req.url === '/duplicates') {
      res.end(JSON.stringify({ duplicate_ids: [42] }));
    } else {
      res.statusCode = 404;
      res.end('{}');
    }
  });
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address() as AddressInfo;
      resolve({ server, url: `http://127.0.0.1:${port}`, seenTokens });
    });
  });
}

describe('ai triage proxy (e2e)', () => {
  let app: INestApplication<App>;
  let alice: TestActor;
  let issueId: number;
  let worker: Awaited<ReturnType<typeof startMockWorker>>;
  const prisma = new PrismaClient();

  beforeAll(async () => {
    worker = await startMockWorker();
    app = await createTestApp();
  });

  beforeEach(async () => {
    process.env.AI_WORKER_URL = worker.url;
    await resetDb(prisma);
    alice = await signupActor(app, 'alice@example.com', 'Alice');
    const team = await prisma.team.findFirstOrThrow({
      where: { workspaceId: alice.workspaceId },
    });
    const res = await request(app.getHttpServer())
      .post('/mutations')
      .set('Authorization', `Bearer ${alice.token}`)
      .send({
        clientMutationId: randomUUID(),
        workspaceId: alice.workspaceId,
        command: {
          type: 'createIssue',
          teamId: team.id,
          title: 'App crashes on login',
        },
      })
      .expect(200);
    issueId = (res.body as MutationResponse).ops[0].entityId;
  });

  afterAll(async () => {
    await app.close();
    await prisma.$disconnect();
    worker.server.close();
  });

  const triage = (actor: TestActor, body: Record<string, unknown>) =>
    request(app.getHttpServer())
      .post('/ai/triage')
      .set('Authorization', `Bearer ${actor.token}`)
      .send(body);

  it('ai-worker 稼働時: suggestion を返し、内部トークンが付与される', async () => {
    const res = await triage(alice, {
      workspaceId: alice.workspaceId,
      issueId,
    }).expect(200);
    const body = res.body as TriageResponse;
    expect(body).toEqual({
      available: true,
      suggestion: {
        priority: 1,
        labels: ['bug'],
        reason: 'mock',
        duplicateIssueIds: [42],
      },
    });
    expect(worker.seenTokens.every((t) => t === 'dev-internal-token')).toBe(
      true,
    );
  });

  it('ai-worker 停止時: available=false に degrade して 200 を返す', async () => {
    process.env.AI_WORKER_URL = 'http://127.0.0.1:1'; // 到達不能
    const res = await triage(alice, {
      workspaceId: alice.workspaceId,
      issueId,
    }).expect(200);
    expect(res.body).toEqual({ available: false, suggestion: null });
  });

  it('非メンバー 403 / 他 workspace の issue 404 / 未認証 401', async () => {
    const mallory = await signupActor(app, 'mallory@example.com', 'Mallory');
    await triage(mallory, { workspaceId: alice.workspaceId, issueId }).expect(
      403,
    );
    await triage(mallory, {
      workspaceId: mallory.workspaceId,
      issueId,
    }).expect(404);
    await request(app.getHttpServer())
      .post('/ai/triage')
      .send({ workspaceId: alice.workspaceId, issueId })
      .expect(401);
  });
});
