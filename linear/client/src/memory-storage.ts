import type { PersistedState, SyncStorage } from './types';

/** テスト・SSR 用のインメモリ storage。ブラウザでは frontend 側の IndexedDB 実装を使う */
export class MemorySyncStorage implements SyncStorage {
  private store = new Map<number, string>();

  load(workspaceId: number): Promise<PersistedState | null> {
    const raw = this.store.get(workspaceId);
    return Promise.resolve(raw ? (JSON.parse(raw) as PersistedState) : null);
  }

  save(state: PersistedState): Promise<void> {
    // 実装間の差異 (構造化クローン vs JSON) を吸収するため JSON 経由にする
    this.store.set(state.workspaceId, JSON.stringify(state));
    return Promise.resolve();
  }
}
