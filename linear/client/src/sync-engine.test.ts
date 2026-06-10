import { beforeEach, describe, expect, it } from 'vitest';
import { DEFAULT_WORKFLOW_STATES } from '@linear/shared';
import type {
  BootstrapResponse,
  DeltaResponse,
  Issue,
  MutationRequest,
  MutationResponse,
  SyncOp,
} from '@linear/shared';
import { MemorySyncStorage } from './memory-storage';
import { SyncEngine } from './sync-engine';
import { TransportHttpError } from './types';
import type { PendingMutation, Transport } from './types';

const T0 = '2026-06-10T12:00:00.000Z';

function issuePayload(
  id: number,
  teamId: number,
  number: number,
  title: string,
  stateId: number,
  sortOrder: string,
): Record<string, unknown> {
  return {
    id,
    teamId,
    number,
    title,
    description: null,
    stateId,
    priority: 0,
    assigneeId: null,
    sortOrder,
    createdById: 1,
    createdAt: T0,
    updatedAt: T0,
  };
}

/** backend のセマンティクスを写した最小サーバ (seq 採番 / 冪等台帳 / id 採番) */
class FakeServer {
  seq = 0;
  nextId = 1000;
  issueNumbers = new Map<number, number>();
  ops: SyncOp[] = [];
  ledger = new Map<string, MutationResponse>();
  failNextStatus: number | null = null;
  networkDown = false;
  mutateCalls: MutationRequest[] = [];

  bootstrap(): BootstrapResponse {
    return {
      workspace: { id: 1, name: 'WS', urlKey: 'ws-1' },
      users: [{ id: 1, name: 'Alice' }],
      members: [{ workspaceId: 1, userId: 1, role: 'admin' }],
      teams: [{ id: 1, workspaceId: 1, key: 'GEN', name: 'General' }],
      states: [
        { id: 100, teamId: 1, name: 'Backlog', category: 'backlog', position: 0 },
        { id: 101, teamId: 1, name: 'Todo', category: 'unstarted', position: 1 },
      ],
      issues: [],
      labels: [],
      issueLabels: [],
      comments: [],
      lastSyncId: this.seq,
    };
  }

  delta(since: number): DeltaResponse {
    return { ops: this.ops.filter((o) => o.seq > since), lastSyncId: this.seq };
  }

  private push(
    partial: Omit<SyncOp, 'seq' | 'workspaceId' | 'actorId'>,
  ): SyncOp {
    const op: SyncOp = { seq: ++this.seq, workspaceId: 1, actorId: 1, ...partial };
    this.ops.push(op);
    return op;
  }

  /** 他 actor による op (WS 配信はテストが receiveServerMessage で行う) */
  externalIssue(title: string): SyncOp {
    const id = this.nextId++;
    const number = (this.issueNumbers.get(1) ?? 0) + 1;
    this.issueNumbers.set(1, number);
    return this.push({
      entityType: 'issue',
      entityId: id,
      action: 'insert',
      clientMutationId: null,
      payload: issuePayload(id, 1, number, title, 100, 'z'),
    });
  }

  externalUpdate(issueId: number, patch: Record<string, unknown>): SyncOp {
    return this.push({
      entityType: 'issue',
      entityId: issueId,
      action: 'update',
      clientMutationId: null,
      payload: { ...patch, updatedAt: T0 },
    });
  }

  mutate(req: MutationRequest): MutationResponse {
    this.mutateCalls.push(req);
    if (this.networkDown) throw new Error('ECONNREFUSED');
    if (this.failNextStatus !== null) {
      const s = this.failNextStatus;
      this.failNextStatus = null;
      throw new TransportHttpError(s);
    }
    const recorded = this.ledger.get(req.clientMutationId);
    if (recorded) return recorded; // 冪等台帳 (ADR 0002)

    const cmid = req.clientMutationId;
    const c = req.command;
    const ops: SyncOp[] = [];
    switch (c.type) {
      case 'createIssue': {
        if (c.teamId < 0 || (c.stateId ?? 1) < 0) throw new TransportHttpError(422);
        const id = this.nextId++;
        const number = (this.issueNumbers.get(c.teamId) ?? 0) + 1;
        this.issueNumbers.set(c.teamId, number);
        ops.push(
          this.push({
            entityType: 'issue',
            entityId: id,
            action: 'insert',
            clientMutationId: cmid,
            payload: issuePayload(
              id,
              c.teamId,
              number,
              c.title,
              c.stateId ?? 100,
              c.sortOrder ?? 'V',
            ),
          }),
        );
        break;
      }
      case 'createTeam': {
        const teamId = this.nextId++;
        ops.push(
          this.push({
            entityType: 'team',
            entityId: teamId,
            action: 'insert',
            clientMutationId: cmid,
            payload: { id: teamId, workspaceId: 1, key: c.key, name: c.name },
          }),
        );
        DEFAULT_WORKFLOW_STATES.forEach((s, i) => {
          const sid = this.nextId++;
          ops.push(
            this.push({
              entityType: 'workflow_state',
              entityId: sid,
              action: 'insert',
              clientMutationId: cmid,
              payload: { id: sid, teamId, name: s.name, category: s.category, position: i },
            }),
          );
        });
        break;
      }
      case 'createComment': {
        if (c.issueId < 0) throw new TransportHttpError(422);
        const id = this.nextId++;
        ops.push(
          this.push({
            entityType: 'comment',
            entityId: id,
            action: 'insert',
            clientMutationId: cmid,
            payload: { id, issueId: c.issueId, authorId: 1, body: c.body, createdAt: T0 },
          }),
        );
        break;
      }
      case 'updateIssue':
        ops.push(
          this.push({
            entityType: 'issue',
            entityId: c.issueId,
            action: 'update',
            clientMutationId: cmid,
            payload: { ...c.patch, updatedAt: T0 },
          }),
        );
        break;
      case 'moveIssue':
        ops.push(
          this.push({
            entityType: 'issue',
            entityId: c.issueId,
            action: 'update',
            clientMutationId: cmid,
            payload: { stateId: c.stateId, sortOrder: c.sortOrder, updatedAt: T0 },
          }),
        );
        break;
      case 'deleteIssue':
        ops.push(
          this.push({
            entityType: 'issue',
            entityId: c.issueId,
            action: 'delete',
            clientMutationId: cmid,
            payload: { id: c.issueId },
          }),
        );
        break;
      default:
        throw new Error(`FakeServer: unsupported command ${c.type}`);
    }
    const res: MutationResponse = { ops, lastSyncId: this.seq };
    this.ledger.set(cmid, res);
    return res;
  }
}

function makeTransport(server: FakeServer): Transport {
  return {
    bootstrap: () => Promise.resolve(server.bootstrap()),
    delta: (_w, since) => Promise.resolve(server.delta(since)),
    mutate: (req) => {
      try {
        return Promise.resolve(server.mutate(req));
      } catch (e) {
        return Promise.reject(e instanceof Error ? e : new Error(String(e)));
      }
    },
  };
}

async function until(cond: () => boolean, ms = 2000): Promise<void> {
  const t0 = Date.now();
  while (!cond()) {
    if (Date.now() - t0 > ms) throw new Error('until: timeout');
    await new Promise((r) => setTimeout(r, 5));
  }
}

describe('SyncEngine', () => {
  let server: FakeServer;
  let storage: MemorySyncStorage;
  let rejected: PendingMutation[];
  let engine: SyncEngine;
  let uuidCounter: number;

  const newEngine = (sharedStorage?: MemorySyncStorage): SyncEngine =>
    new SyncEngine({
      workspaceId: 1,
      actorId: 1,
      transport: makeTransport(server),
      storage: sharedStorage ?? storage,
      now: () => T0,
      uuid: () =>
        `00000000-0000-4000-8000-${String(++uuidCounter).padStart(12, '0')}`,
      onMutationRejected: (p) => rejected.push(p),
    });

  const issues = (): Issue[] => Object.values(engine.getSnapshot().state.issues);
  const settled = () => until(() => engine.getSnapshot().pendingCount === 0);

  beforeEach(async () => {
    server = new FakeServer();
    storage = new MemorySyncStorage();
    rejected = [];
    uuidCounter = 0;
    engine = newEngine();
    await engine.start();
  });

  it('初回 start は bootstrap から state を作る', () => {
    const snap = engine.getSnapshot();
    expect(snap.status).toBe('ready');
    expect(snap.lastSyncId).toBe(0);
    expect(Object.keys(snap.state.teams)).toHaveLength(1);
    expect(Object.keys(snap.state.states)).toHaveLength(2);
  });

  it('mutate は即座に楽観反映され、確定で実 id に置き換わる', async () => {
    engine.mutate({ type: 'createIssue', teamId: 1, title: 'Hello' });

    // 同期的に楽観反映 (temp id は負数 / number はプレースホルダ 0)
    const optimistic = issues();
    expect(optimistic).toHaveLength(1);
    expect(optimistic[0]!.id).toBeLessThan(0);
    expect(optimistic[0]!.number).toBe(0);
    expect(optimistic[0]!.stateId).toBe(100); // normalizeCommand が既定 state を確定

    await settled();
    const confirmed = issues();
    expect(confirmed).toHaveLength(1);
    expect(confirmed[0]!.id).toBe(1000);
    expect(confirmed[0]!.number).toBe(1);
    expect(engine.getSnapshot().lastSyncId).toBe(1);
  });

  it('他 actor の op (WS) が confirmed に適用される', () => {
    const op = server.externalIssue('From Bob');
    engine.receiveServerMessage({ type: 'op', op });
    expect(issues()).toHaveLength(1);
    expect(engine.getSnapshot().lastSyncId).toBe(1);
  });

  it('rebase: pending 中に他者の op が来ても両方の変更が表示に残る', async () => {
    engine.mutate({ type: 'createIssue', teamId: 1, title: 'Mine' });
    await settled();
    const issueId = issues()[0]!.id;

    engine.setOnline(false);
    engine.mutate({ type: 'updateIssue', issueId, patch: { title: 'Renamed locally' } });

    const op = server.externalUpdate(issueId, { priority: 2 });
    engine.receiveServerMessage({ type: 'op', op });

    // confirmed の priority と pending の title が同時に見える (rebase)
    expect(issues()[0]).toMatchObject({ title: 'Renamed locally', priority: 2 });

    engine.setOnline(true);
    await settled();
    expect(issues()[0]).toMatchObject({ title: 'Renamed locally', priority: 2 });
  });

  it('4xx 拒否は pending を破棄して表示が巻き戻る (rollback)', async () => {
    engine.mutate({ type: 'createIssue', teamId: 1, title: 'Original' });
    await settled();
    const issueId = issues()[0]!.id;

    server.failNextStatus = 422;
    engine.mutate({ type: 'updateIssue', issueId, patch: { title: 'Doomed' } });
    expect(issues()[0]!.title).toBe('Doomed'); // 楽観反映

    await settled();
    expect(issues()[0]!.title).toBe('Original'); // rollback
    expect(rejected).toHaveLength(1);
  });

  it('offline queue: 一時 id 参照が実 id に書き換えられて順に replay される', async () => {
    engine.setOnline(false);
    engine.mutate({ type: 'createIssue', teamId: 1, title: 'Offline parent' });
    const tempIssueId = issues()[0]!.id;
    expect(tempIssueId).toBeLessThan(0);
    engine.mutate({ type: 'createComment', issueId: tempIssueId, body: 'on temp' });

    expect(server.mutateCalls).toHaveLength(0); // オフライン中は送らない
    expect(Object.keys(engine.getSnapshot().state.comments)).toHaveLength(1);

    engine.setOnline(true);
    await settled();

    expect(server.mutateCalls).toHaveLength(2);
    const commentCall = server.mutateCalls[1]!.command;
    expect(commentCall.type).toBe('createComment');
    if (commentCall.type === 'createComment') {
      expect(commentCall.issueId).toBe(1000); // remap 済み
    }
    const comments = Object.values(engine.getSnapshot().state.comments);
    expect(comments[0]!.issueId).toBe(1000);
  });

  it('依存先が拒否されたら、その一時 id を参照する後続も連鎖破棄される', async () => {
    engine.setOnline(false);
    engine.mutate({ type: 'createIssue', teamId: 1, title: 'Will fail' });
    const tempIssueId = issues()[0]!.id;
    engine.mutate({ type: 'createComment', issueId: tempIssueId, body: 'orphan' });

    server.failNextStatus = 422;
    engine.setOnline(true);
    await settled();

    expect(server.mutateCalls).toHaveLength(1); // comment は送られない
    expect(rejected).toHaveLength(2);
    expect(issues()).toHaveLength(0);
    expect(Object.keys(engine.getSnapshot().state.comments)).toHaveLength(0);
  });

  it('重複 op (seq <= lastSyncId) は無視する', async () => {
    engine.mutate({ type: 'createIssue', teamId: 1, title: 'Once' });
    await settled();
    const op = server.ops[0]!;
    engine.receiveServerMessage({ type: 'op', op }); // HTTP response と二重到着
    expect(issues()).toHaveLength(1);
  });

  it('gap を検出したら delta で自己修復する', async () => {
    server.externalIssue('a'); // seq 1 (未受信)
    server.externalIssue('b'); // seq 2 (未受信)
    const op3 = server.externalIssue('c'); // seq 3 のみ届く

    engine.receiveServerMessage({ type: 'op', op: op3 });
    await until(() => engine.getSnapshot().lastSyncId === 3);
    expect(issues()).toHaveLength(3);
  });

  it('hello の lastSyncId が進んでいたら catch-up する', async () => {
    server.externalIssue('missed');
    engine.receiveServerMessage({ type: 'hello', workspaceId: 1, lastSyncId: 1 });
    await until(() => engine.getSnapshot().lastSyncId === 1);
    expect(issues()).toHaveLength(1);
  });

  it('deleteIssue の確定で comments もカスケードされる', async () => {
    engine.mutate({ type: 'createIssue', teamId: 1, title: 'To delete' });
    await settled();
    const issueId = issues()[0]!.id;
    engine.mutate({ type: 'createComment', issueId, body: 'bye' });
    await settled();
    engine.mutate({ type: 'deleteIssue', issueId });
    await settled();

    expect(issues()).toHaveLength(0);
    expect(Object.keys(engine.getSnapshot().state.comments)).toHaveLength(0);
  });

  it('createTeam (multi-op): temp team を参照する後続 createIssue も remap される', async () => {
    engine.setOnline(false);
    engine.mutate({ type: 'createTeam', key: 'ENG', name: 'Engineering' });
    const tempTeam = Object.values(engine.getSnapshot().state.teams).find(
      (t) => t.id < 0,
    )!;
    expect(
      Object.values(engine.getSnapshot().state.states).filter(
        (s) => s.teamId === tempTeam.id,
      ),
    ).toHaveLength(5);

    engine.mutate({ type: 'createIssue', teamId: tempTeam.id, title: 'In new team' });

    engine.setOnline(true);
    await settled();

    const issueCall = server.mutateCalls[1]!.command;
    expect(issueCall.type).toBe('createIssue');
    if (issueCall.type === 'createIssue') {
      expect(issueCall.teamId).toBeGreaterThan(0); // team remap
      expect(issueCall.stateId).toBeGreaterThan(0); // state remap (既定 state も temp だった)
    }
    const confirmedIssue = issues()[0]!;
    expect(confirmedIssue.teamId).toBeGreaterThan(0);
  });

  it('永続化: 別 engine が pending を復元して replay できる', async () => {
    engine.setOnline(false);
    engine.mutate({ type: 'createIssue', teamId: 1, title: 'Persisted' });
    await until(() => server.mutateCalls.length === 0); // 永続化は非同期なので一拍待つ
    await new Promise((r) => setTimeout(r, 20));

    const engine2 = newEngine(storage);
    await engine2.start(); // catch-up → replay
    await until(() => engine2.getSnapshot().pendingCount === 0);

    expect(server.mutateCalls).toHaveLength(1);
    const revived = Object.values(engine2.getSnapshot().state.issues);
    expect(revived).toHaveLength(1);
    expect(revived[0]!.id).toBe(1000);
  });

  it('変化が無ければ getSnapshot は同一参照を返す (useSyncExternalStore 互換)', () => {
    const a = engine.getSnapshot();
    const b = engine.getSnapshot();
    expect(a).toBe(b);
  });
});
