import {
  appendOrderKey,
  applyCommand,
  applyOp,
  defaultStateId,
  emptySnapshot,
  fromBootstrap,
  tempIdCount,
} from '@linear/shared';
import type {
  MutationCommand,
  MutationResponse,
  ServerWsMessage,
  SyncOp,
  WorkspaceSnapshot,
} from '@linear/shared';
import {
  TransportHttpError,
  type EngineSnapshot,
  type EngineStatus,
  type PendingMutation,
  type SyncStorage,
  type Transport,
} from './types';

export interface SyncEngineOptions {
  workspaceId: number;
  actorId: number;
  transport: Transport;
  storage: SyncStorage;
  /** 注入可能な時計 / id 採番 (テストの決定性のため) */
  now?: () => string;
  uuid?: () => string;
  /** server が mutation を拒否 (4xx) した時。rollback 自体は engine が行う */
  onMutationRejected?: (entry: PendingMutation, error: unknown) => void;
}

/**
 * client sync engine (ADR 0003)。
 *
 * - confirmed (server 確定 state) と pending (未確定 mutation 列) を分離し、
 *   表示は `confirmed に pending を順に applyCommand した導出値` (rebase 方式)
 * - op の取り込みは seq 連続性のみを信じる: 重複 (seq <= lastSyncId) は捨て、
 *   gap は delta で自己修復する (push は at-most-once のヒント / ADR 0005)
 * - 送信は FIFO 直列。一時 id (負数) を含むコマンドは、先行 mutation の確定で
 *   実 id に書き換えられてから送られる (offline replay でも成立)
 * - 4xx 拒否は該当 pending を破棄 = 自動 rollback。その一時 id に依存する
 *   後続 pending も連鎖破棄する。5xx / ネットワーク断は保留して再試行
 *   (再送重複は server の clientMutationId 冪等台帳が吸収)
 */
export class SyncEngine {
  private readonly workspaceId: number;
  private readonly actorId: number;
  private readonly transport: Transport;
  private readonly storage: SyncStorage;
  private readonly now: () => string;
  private readonly uuid: () => string;
  private readonly onMutationRejected?: (
    entry: PendingMutation,
    error: unknown,
  ) => void;

  private confirmed: WorkspaceSnapshot = emptySnapshot();
  private lastSyncId = 0;
  private pending: PendingMutation[] = [];
  private nextTempId = -1;
  /** 確定 op の insert と位置対応させる、確定中 mutation の未消費一時 id */
  private confirmingTempQueues = new Map<string, number[]>();
  private confirmedMutationIds = new Set<string>();

  private online = true;
  private status: EngineStatus = 'idle';
  private flushing = false;
  private catchingUp = false;

  private listeners = new Set<() => void>();
  private cache: EngineSnapshot | null = null;

  constructor(opts: SyncEngineOptions) {
    this.workspaceId = opts.workspaceId;
    this.actorId = opts.actorId;
    this.transport = opts.transport;
    this.storage = opts.storage;
    this.now = opts.now ?? (() => new Date().toISOString());
    this.uuid = opts.uuid ?? (() => crypto.randomUUID());
    this.onMutationRejected = opts.onMutationRejected;
  }

  // ─── store interface (React useSyncExternalStore 互換) ───────────────────

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getSnapshot = (): EngineSnapshot => {
    if (!this.cache) {
      this.cache = {
        state: this.derive(),
        lastSyncId: this.lastSyncId,
        pendingCount: this.pending.length,
        online: this.online,
        status: this.status,
      };
    }
    return this.cache;
  };

  // ─── ライフサイクル ──────────────────────────────────────────────────────

  /** 起動: storage 復元 → catch-up、無ければ bootstrap。その後 pending replay */
  async start(): Promise<void> {
    this.status = 'loading';
    this.notify();
    const persisted = await this.storage.load(this.workspaceId);
    if (persisted) {
      this.confirmed = persisted.confirmed;
      this.lastSyncId = persisted.lastSyncId;
      this.pending = persisted.pending;
      this.nextTempId = persisted.nextTempId;
      await this.catchUp();
    } else {
      const b = await this.transport.bootstrap(this.workspaceId);
      this.confirmed = fromBootstrap(b);
      this.lastSyncId = b.lastSyncId;
    }
    this.status = 'ready';
    this.notify();
    await this.persist();
    await this.flush();
  }

  setOnline(online: boolean): void {
    if (this.online === online) return;
    this.online = online;
    this.notify();
    if (online) {
      // 再接続シーケンス (ADR 0003): ① delta catch-up → ③ pending replay
      void this.catchUp().then(() => this.flush());
    }
  }

  /** WS からの server メッセージ (frontend の WSClient が中継する) */
  receiveServerMessage(msg: ServerWsMessage): void {
    if (msg.type === 'hello') {
      // (再) 接続 = server 到達可能。catch-up してから保留分を replay する
      void this.catchUp().then(() => this.flush());
      return;
    }
    this.ingestOps([msg.op]);
  }

  // ─── mutation ────────────────────────────────────────────────────────────

  /** 楽観適用して送信キューに積む。戻り値は clientMutationId */
  mutate(command: MutationCommand): string {
    const normalized = this.normalizeCommand(command);
    const tempIds = Array.from(
      { length: tempIdCount(normalized) },
      () => this.nextTempId--,
    );
    const entry: PendingMutation = {
      clientMutationId: this.uuid(),
      command: normalized,
      tempIds,
      nowIso: this.now(),
    };
    this.pending.push(entry);
    this.notify();
    void this.persist();
    void this.flush();
    return entry.clientMutationId;
  }

  /**
   * 楽観適用と server 適用を一致させるため、server 側でデフォルトが決まる
   * フィールド (stateId / sortOrder) は送信前に client が確定させる
   */
  private normalizeCommand(command: MutationCommand): MutationCommand {
    if (command.type !== 'createIssue') return command;
    const display = this.derive();
    const stateId = command.stateId ?? defaultStateId(display, command.teamId);
    const sortOrder =
      command.sortOrder ?? appendOrderKey(display, command.teamId, stateId);
    return { ...command, stateId, sortOrder };
  }

  // ─── op の取り込み (唯一の confirmed 更新経路) ────────────────────────────

  private ingestOps(ops: SyncOp[]): void {
    let changed = false;
    for (const op of ops) {
      if (op.seq <= this.lastSyncId) continue; // 重複 (WS と HTTP response の二重到着)
      if (op.seq !== this.lastSyncId + 1) {
        // gap: 取りこぼしがあるので log から埋め直す (ADR 0005)
        void this.catchUp();
        break;
      }
      this.confirmed = applyOp(this.confirmed, op);
      this.lastSyncId = op.seq;
      changed = true;
      if (op.clientMutationId) this.noteOwnOp(op);
    }
    if (changed) {
      this.notify();
      void this.persist();
    }
  }

  /** 自分の mutation の確定: pending を外し、一時 id → 実 id を解決する */
  private noteOwnOp(op: SyncOp): void {
    const cmid = op.clientMutationId as string;
    const idx = this.pending.findIndex((p) => p.clientMutationId === cmid);
    if (idx >= 0) {
      const entry = this.pending[idx] as PendingMutation;
      this.confirmingTempQueues.set(cmid, [...entry.tempIds]);
      this.pending.splice(idx, 1);
      this.confirmedMutationIds.add(cmid);
    }
    // insert op は mutate() 時の一時 id 割当てと同順で届く (backend の draft 生成順)
    if (op.action === 'insert' && op.entityType !== 'issue_label') {
      const queue = this.confirmingTempQueues.get(cmid);
      const temp = queue?.shift();
      if (temp !== undefined) this.remapPending(temp, op.entityId);
    }
  }

  /** 後続 pending コマンド内の一時 id 参照を実 id へ書き換える */
  private remapPending(temp: number, real: number): void {
    this.pending = this.pending.map((p) => ({
      ...p,
      command: deepReplaceNumber(p.command, temp, real) as MutationCommand,
    }));
  }

  // ─── 送信 (FIFO 直列) ────────────────────────────────────────────────────

  private async flush(): Promise<void> {
    if (this.flushing || !this.online || this.status !== 'ready') return;
    this.flushing = true;
    try {
      while (this.online && this.pending.length > 0) {
        const head = this.pending[0] as PendingMutation;
        if (referencesUnresolvedTemp(head.command)) {
          // 依存先が rollback で消えた孤児 (FIFO なので正常系では起きない)
          this.reject(head, new Error('depends on a rolled-back mutation'));
          continue;
        }
        try {
          const res = await this.transport.mutate({
            clientMutationId: head.clientMutationId,
            workspaceId: this.workspaceId,
            command: head.command,
          });
          await this.noteResponse(res);
        } catch (e) {
          if (
            e instanceof TransportHttpError &&
            e.status >= 400 &&
            e.status < 500
          ) {
            this.reject(head, e); // rollback (ADR 0003)
            continue;
          }
          break; // ネットワーク断 / 5xx: 保留して次の機会に再送 (at-least-once)
        }
      }
    } finally {
      this.flushing = false;
      this.notify();
      void this.persist();
    }
  }

  /** HTTP response の ops を取り込む。間に他者の op が挟まっていたら先に catch-up */
  private async noteResponse(res: MutationResponse): Promise<void> {
    const first = res.ops[0];
    if (first && first.seq > this.lastSyncId + 1) {
      await this.catchUp(); // catch-up 自体が自分の ops も連れてくる
    }
    this.ingestOps(res.ops); // 既に取り込み済みなら seq dedup で no-op
  }

  /** 4xx 拒否: pending から外す = 表示が自動で巻き戻る。依存する後続も連鎖破棄 */
  private reject(entry: PendingMutation, error: unknown): void {
    this.pending = this.pending.filter((p) => p !== entry);
    this.onMutationRejected?.(entry, error);

    // entry が作るはずだった一時 id を参照する後続を、不動点まで連鎖破棄する
    let orphanTemps = entry.tempIds;
    while (orphanTemps.length > 0) {
      const nextOrphans: number[] = [];
      this.pending = this.pending.filter((p) => {
        if (orphanTemps.some((t) => referencesNumber(p.command, t))) {
          nextOrphans.push(...p.tempIds);
          this.onMutationRejected?.(p, error);
          return false;
        }
        return true;
      });
      orphanTemps = nextOrphans;
    }
    this.notify();
    void this.persist();
  }

  // ─── catch-up / 導出 / 永続化 ────────────────────────────────────────────

  private async catchUp(): Promise<void> {
    if (this.catchingUp || !this.online) return;
    this.catchingUp = true;
    try {
      const d = await this.transport.delta(this.workspaceId, this.lastSyncId);
      this.ingestOps(d.ops);
    } catch {
      // 取得失敗 = 実質オフライン。次の online / hello / gap 検出で再試行する
    } finally {
      this.catchingUp = false;
    }
  }

  private derive(): WorkspaceSnapshot {
    let state = this.confirmed;
    for (const p of this.pending) {
      if (this.confirmedMutationIds.has(p.clientMutationId)) continue; // 防御
      state = applyCommand(state, p.command, {
        actorId: this.actorId,
        tempIds: p.tempIds,
        nowIso: p.nowIso,
      });
    }
    return state;
  }

  private notify(): void {
    this.cache = null;
    for (const listener of this.listeners) listener();
  }

  private async persist(): Promise<void> {
    try {
      await this.storage.save({
        workspaceId: this.workspaceId,
        lastSyncId: this.lastSyncId,
        confirmed: this.confirmed,
        pending: this.pending,
        nextTempId: this.nextTempId,
      });
    } catch {
      // 永続化失敗は致命ではない (次回 bootstrap で復元できる)
    }
  }
}

// ─── command 内の数値 id 走査ユーティリティ ──────────────────────────────────

function deepReplaceNumber(value: unknown, from: number, to: number): unknown {
  if (value === from) return to;
  if (Array.isArray(value)) {
    return value.map((v) => deepReplaceNumber(v, from, to));
  }
  if (value !== null && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value)) {
      out[k] = deepReplaceNumber(v, from, to);
    }
    return out;
  }
  return value;
}

function referencesNumber(value: unknown, target: number): boolean {
  if (value === target) return true;
  if (Array.isArray(value)) return value.some((v) => referencesNumber(v, target));
  if (value !== null && typeof value === 'object') {
    return Object.values(value).some((v) => referencesNumber(v, target));
  }
  return false;
}

/** 一時 id (負数) への参照が残っているか。idempotency のため id フィールドのみが負になり得る */
function referencesUnresolvedTemp(value: unknown): boolean {
  if (typeof value === 'number') return value < 0;
  if (Array.isArray(value)) return value.some(referencesUnresolvedTemp);
  if (value !== null && typeof value === 'object') {
    return Object.values(value).some(referencesUnresolvedTemp);
  }
  return false;
}
