import type { PersistedState, SyncStorage } from '@linear/client-sync';

const DB_NAME = 'linear-sync';
const STORE = 'workspaces';

/**
 * SyncEngine の永続化先 (ADR 0003: リロード・オフライン起動からの復元)。
 * 1 workspace = 1 レコードの粗粒度 put で十分なため、ライブラリなしの
 * 素の IndexedDB を Promise で包むだけにしている。
 */
export class IdbSyncStorage implements SyncStorage {
  private db: Promise<IDBDatabase> | null = null;

  private open(): Promise<IDBDatabase> {
    this.db ??= new Promise((resolve, reject) => {
      const req = indexedDB.open(DB_NAME, 1);
      req.onupgradeneeded = () => req.result.createObjectStore(STORE);
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error ?? new Error('indexedDB open failed'));
    });
    return this.db;
  }

  async load(workspaceId: number): Promise<PersistedState | null> {
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const req = db
        .transaction(STORE, 'readonly')
        .objectStore(STORE)
        .get(workspaceId);
      req.onsuccess = () =>
        resolve((req.result as PersistedState | undefined) ?? null);
      req.onerror = () => reject(req.error ?? new Error('idb get failed'));
    });
  }

  async save(state: PersistedState): Promise<void> {
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE, 'readwrite');
      tx.objectStore(STORE).put(state, state.workspaceId);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error ?? new Error('idb put failed'));
    });
  }
}
