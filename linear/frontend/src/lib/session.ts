/**
 * 認証セッションの localStorage 同期 (docs/coding-rules/frontend.md の定石):
 * useSyncExternalStore + 同一タブには synthetic 'storage' event で通知する。
 */

export interface Session {
  token: string;
  user: { id: number; email: string; name: string };
  workspace: { id: number; name: string; urlKey: string };
}

const KEY = 'linear.session';
let cache: { raw: string | null; value: Session | null } = {
  raw: null,
  value: null,
};

export function getSession(): Session | null {
  if (typeof window === 'undefined') return null;
  const raw = window.localStorage.getItem(KEY);
  if (raw === cache.raw) return cache.value; // 参照安定 (useSyncExternalStore 用)
  cache = { raw, value: raw ? (JSON.parse(raw) as Session) : null };
  return cache.value;
}

export function setSession(session: Session | null): void {
  if (session) window.localStorage.setItem(KEY, JSON.stringify(session));
  else window.localStorage.removeItem(KEY);
  window.dispatchEvent(new StorageEvent('storage', { key: KEY }));
}

export function subscribeSession(listener: () => void): () => void {
  window.addEventListener('storage', listener);
  return () => window.removeEventListener('storage', listener);
}
