import type {
  BootstrapResponse,
  DeltaResponse,
  MutationCommand,
  MutationRequest,
  MutationResponse,
  WorkspaceSnapshot,
} from '@linear/shared';

/**
 * server との通信口。frontend では fetch 実装、テストでは FakeServer を注入する。
 * 4xx は TransportHttpError を投げること (engine が「拒否 = rollback」と解釈する)。
 * ネットワーク断・5xx はその他の例外 = リトライ対象。
 */
export interface Transport {
  bootstrap(workspaceId: number): Promise<BootstrapResponse>;
  delta(workspaceId: number, since: number): Promise<DeltaResponse>;
  mutate(req: MutationRequest): Promise<MutationResponse>;
}

export class TransportHttpError extends Error {
  constructor(
    readonly status: number,
    message = `HTTP ${status}`,
  ) {
    super(message);
    this.name = 'TransportHttpError';
  }
}

/** 未確定 mutation (pending queue の 1 エントリ)。再導出のため全フィールド固定値 */
export interface PendingMutation {
  clientMutationId: string;
  command: MutationCommand;
  /** mutate() 時に固定割当てした一時 id (負数)。確定 op と位置対応で実 id に解決される */
  tempIds: number[];
  nowIso: string;
}

/** IndexedDB / メモリへ永続化する形 (ADR 0003: リロード・オフライン起動から復元) */
export interface PersistedState {
  workspaceId: number;
  lastSyncId: number;
  confirmed: WorkspaceSnapshot;
  pending: PendingMutation[];
  nextTempId: number;
}

export interface SyncStorage {
  load(workspaceId: number): Promise<PersistedState | null>;
  save(state: PersistedState): Promise<void>;
}

export type EngineStatus = 'idle' | 'loading' | 'ready';

/** useSyncExternalStore へ渡す不変 snapshot */
export interface EngineSnapshot {
  state: WorkspaceSnapshot;
  lastSyncId: number;
  pendingCount: number;
  online: boolean;
  status: EngineStatus;
}
