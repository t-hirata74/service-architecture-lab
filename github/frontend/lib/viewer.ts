// 開発用: localStorage に X-User-Login を保存して urql の fetch でヘッダに乗せる。
// Phase 5b では auth 自体は backend 側のスタブと同じく "ヘッダで viewer 切替" のみ。
const KEY = "x-user-login";

export function getViewerLogin(): string | null {
  if (typeof window === "undefined") return null;
  return window.localStorage.getItem(KEY);
}

export function setViewerLogin(login: string | null): void {
  if (typeof window === "undefined") return;
  if (login && login.length > 0) {
    window.localStorage.setItem(KEY, login);
  } else {
    window.localStorage.removeItem(KEY);
  }
  // urql の同 client インスタンス内で再 fetch を走らせるため hard reload
  window.location.reload();
}
