import { randomUUID } from 'node:crypto';
import { INestApplication } from '@nestjs/common';
import type { DeltaResponse, ServerWsMessage } from '@linear/shared';
import {
  ServerWsMessageSchema,
  WS_CLOSE_FORBIDDEN,
  WS_CLOSE_INVALID_PARAMS,
  WS_CLOSE_UNAUTHORIZED,
} from '@linear/shared';
import { PrismaClient } from '@prisma/client';
import request from 'supertest';
import { App } from 'supertest/types';
import WebSocket from 'ws';
import { listenTestApp, resetDb, signupActor, TestActor } from './helpers';

class WsProbe {
  readonly messages: ServerWsMessage[] = [];
  readonly closed: Promise<number>;

  constructor(readonly ws: WebSocket) {
    ws.on('message', (data: Buffer) => {
      this.messages.push(ServerWsMessageSchema.parse(JSON.parse(String(data))));
    });
    this.closed = new Promise((resolve) =>
      ws.on('close', (code: number) => resolve(code)),
    );
  }

  ops(): ServerWsMessage[] {
    return this.messages.filter((m) => m.type === 'op');
  }

  async waitFor(
    pred: (messages: ServerWsMessage[]) => boolean,
    timeoutMs = 3_000,
  ): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    while (!pred(this.messages)) {
      if (Date.now() > deadline) {
        throw new Error(
          `WsProbe timeout. got: ${JSON.stringify(this.messages)}`,
        );
      }
      await new Promise((r) => setTimeout(r, 10));
    }
  }

  close(): void {
    this.ws.close();
  }
}

describe('realtime WS gateway (e2e)', () => {
  let app: INestApplication<App>;
  let port: number;
  let alice: TestActor;
  let teamId: number;
  const prisma = new PrismaClient();
  const probes: WsProbe[] = [];

  const connect = (workspaceId: number, token: string): WsProbe => {
    const probe = new WsProbe(
      new WebSocket(
        `ws://127.0.0.1:${port}/sync/ws?workspaceId=${workspaceId}&token=${encodeURIComponent(token)}`,
      ),
    );
    probes.push(probe);
    return probe;
  };

  const mutate = (
    actor: TestActor,
    title: string,
    clientMutationId = randomUUID(),
  ) =>
    request(app.getHttpServer())
      .post('/mutations')
      .set('Authorization', `Bearer ${actor.token}`)
      .send({
        clientMutationId,
        workspaceId: actor.workspaceId,
        command: { type: 'createIssue', teamId, title },
      })
      .expect(200);

  beforeAll(async () => {
    ({ app, port } = await listenTestApp());
  });

  beforeEach(async () => {
    await resetDb(prisma);
    alice = await signupActor(app, 'alice@example.com', 'Alice');
    const team = await prisma.team.findFirstOrThrow({
      where: { workspaceId: alice.workspaceId },
    });
    teamId = team.id;
  });

  afterEach(() => {
    for (const p of probes.splice(0)) p.close();
  });

  afterAll(async () => {
    await app.close();
    await prisma.$disconnect();
  });

  it('接続直後に hello (現在の lastSyncId) が届く', async () => {
    const probe = connect(alice.workspaceId, alice.token);
    await probe.waitFor((m) => m.some((x) => x.type === 'hello'));
    expect(probe.messages[0]).toEqual({
      type: 'hello',
      workspaceId: alice.workspaceId,
      lastSyncId: 0,
    });
  });

  it('mutation の op が同一 workspace の 2 接続へ fan-out される', async () => {
    const a = connect(alice.workspaceId, alice.token);
    const b = connect(alice.workspaceId, alice.token);
    await a.waitFor((m) => m.some((x) => x.type === 'hello'));
    await b.waitFor((m) => m.some((x) => x.type === 'hello'));

    await mutate(alice, 'realtime!');

    for (const probe of [a, b]) {
      await probe.waitFor((m) => m.some((x) => x.type === 'op'));
      const op = probe.ops()[0];
      expect(op).toMatchObject({
        type: 'op',
        op: { seq: 1, entityType: 'issue', action: 'insert' },
      });
    }
  });

  it('冪等 replay は再 broadcast しない', async () => {
    const probe = connect(alice.workspaceId, alice.token);
    await probe.waitFor((m) => m.some((x) => x.type === 'hello'));

    const cmid = randomUUID();
    await mutate(alice, 'once', cmid);
    await probe.waitFor((m) => m.filter((x) => x.type === 'op').length === 1);

    await mutate(alice, 'once', cmid); // 再送 (at-least-once)
    await new Promise((r) => setTimeout(r, 300));
    expect(probe.ops()).toHaveLength(1);
  });

  it('再接続: hello の lastSyncId から delta で catch-up できる', async () => {
    const probe = connect(alice.workspaceId, alice.token);
    await probe.waitFor((m) => m.some((x) => x.type === 'hello'));

    await mutate(alice, 'before disconnect'); // seq 1
    await probe.waitFor((m) => m.some((x) => x.type === 'op'));
    probe.close();
    await probe.closed;

    await mutate(alice, 'while offline'); // seq 2 (切断中 → push は届かない)

    const again = connect(alice.workspaceId, alice.token);
    await again.waitFor((m) => m.some((x) => x.type === 'hello'));
    const hello = again.messages[0] as Extract<
      ServerWsMessage,
      { type: 'hello' }
    >;
    expect(hello.lastSyncId).toBe(2);

    // client の再接続手順 (ADR 0003/0005): 手元の lastSyncId=1 から delta で埋める
    const res = await request(app.getHttpServer())
      .get(`/sync/delta?workspaceId=${alice.workspaceId}&since=1`)
      .set('Authorization', `Bearer ${alice.token}`)
      .expect(200);
    const delta = res.body as DeltaResponse;
    expect(delta.ops.map((o) => o.seq)).toEqual([2]);
  });

  it('removeMember で本人の socket が 4403 で切られ、他メンバーには delete op が届く', async () => {
    const bob = await signupActor(app, 'bob@example.com', 'Bob');
    await mutate(alice, 'seed (invite 前)'); // seq 1
    await request(app.getHttpServer())
      .post('/mutations')
      .set('Authorization', `Bearer ${alice.token}`)
      .send({
        clientMutationId: randomUUID(),
        workspaceId: alice.workspaceId,
        command: {
          type: 'inviteMember',
          email: 'bob@example.com',
          role: 'member',
        },
      })
      .expect(200); // seq 2

    const aliceProbe = connect(alice.workspaceId, alice.token);
    const bobProbe = connect(alice.workspaceId, bob.token);
    await aliceProbe.waitFor((m) => m.some((x) => x.type === 'hello'));
    await bobProbe.waitFor((m) => m.some((x) => x.type === 'hello'));

    await request(app.getHttpServer())
      .post('/mutations')
      .set('Authorization', `Bearer ${alice.token}`)
      .send({
        clientMutationId: randomUUID(),
        workspaceId: alice.workspaceId,
        command: { type: 'removeMember', userId: bob.userId },
      })
      .expect(200); // seq 3

    expect(await bobProbe.closed).toBe(WS_CLOSE_FORBIDDEN); // kick (ADR 0006)
    await aliceProbe.waitFor((m) =>
      m.some(
        (x) =>
          x.type === 'op' &&
          x.op.entityType === 'workspace_member' &&
          x.op.action === 'delete',
      ),
    );
    // 再接続も拒否される
    const again = connect(alice.workspaceId, bob.token);
    expect(await again.closed).toBe(WS_CLOSE_FORBIDDEN);
  });

  it('拒否: 不正 token=4401 / 非メンバー=4403 / 不正 workspaceId=4400', async () => {
    const bad = connect(alice.workspaceId, 'broken-token');
    expect(await bad.closed).toBe(WS_CLOSE_UNAUTHORIZED);

    const mallory = await signupActor(app, 'mallory@example.com', 'Mallory');
    const forbidden = connect(alice.workspaceId, mallory.token);
    expect(await forbidden.closed).toBe(WS_CLOSE_FORBIDDEN);

    const invalid = connect(0, alice.token);
    expect(await invalid.closed).toBe(WS_CLOSE_INVALID_PARAMS);
  });
});
