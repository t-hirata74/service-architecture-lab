"use client";

import { useCallback, useMemo, useSyncExternalStore } from "react";
import { ApiUser, TOKEN_STORAGE_KEY, USER_STORAGE_KEY } from "./api";

/** localStorage の特定 key を React に橋渡しする。
 * `set-state-in-effect` 警告を避けつつ、login/logout の他タブ反映 (storage event) も拾う。
 */
function useLocalStorageRaw(key: string): string | null {
  const subscribe = useCallback((cb: () => void) => {
    if (typeof window === "undefined") return () => {};
    window.addEventListener("storage", cb);
    return () => window.removeEventListener("storage", cb);
  }, []);
  const getSnapshot = useCallback(() => {
    if (typeof window === "undefined") return null;
    return window.localStorage.getItem(key);
  }, [key]);
  return useSyncExternalStore(subscribe, getSnapshot, () => null);
}

export function useStoredUser(): ApiUser | null {
  const raw = useLocalStorageRaw(USER_STORAGE_KEY);
  return useMemo(() => {
    if (!raw) return null;
    try {
      return JSON.parse(raw) as ApiUser;
    } catch {
      return null;
    }
  }, [raw]);
}

export function useStoredToken(): string | null {
  return useLocalStorageRaw(TOKEN_STORAGE_KEY);
}

/** SSR 時 false / hydration 後 true を返す。
 * AuthGuard で「マウント前に redirect しない」ためのガード用。
 */
export function useHasMounted(): boolean {
  const subscribe = useCallback(() => () => {}, []);
  const getSnapshot = useCallback(() => true, []);
  const getServerSnapshot = useCallback(() => false, []);
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}
