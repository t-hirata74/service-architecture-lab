// Phase 2: rodauth-rails が `/login` 成功時に Authorization レスポンスヘッダで返す JWT を
// localStorage に保存し、以降の cart / checkout に Bearer で付ける。
// shop ごとに別 token として管理する (買い物客は shop に bind されているため)。

import { useEffect, useState } from "react";

const KEY = (sub: string) => `shopify_lab.jwt.${sub}`;
const EMAIL_KEY = (sub: string) => `shopify_lab.email.${sub}`;

export function getToken(shopSubdomain: string): string | null {
  if (typeof window === "undefined") return null;
  return window.localStorage.getItem(KEY(shopSubdomain));
}

export function setToken(shopSubdomain: string, token: string, email: string) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(KEY(shopSubdomain), token);
  window.localStorage.setItem(EMAIL_KEY(shopSubdomain), email);
  window.dispatchEvent(new Event("shopify_lab:auth_changed"));
}

export function clearToken(shopSubdomain: string) {
  if (typeof window === "undefined") return;
  window.localStorage.removeItem(KEY(shopSubdomain));
  window.localStorage.removeItem(EMAIL_KEY(shopSubdomain));
  window.dispatchEvent(new Event("shopify_lab:auth_changed"));
}

export function getEmail(shopSubdomain: string): string | null {
  if (typeof window === "undefined") return null;
  return window.localStorage.getItem(EMAIL_KEY(shopSubdomain));
}

export function useAuth(shopSubdomain: string): { email: string | null; token: string | null } {
  // 初回 render から localStorage を見る (lazy initializer)。
  // useEffect で遅延ロードすると、cart 等の "未ログインなら /login へ" 判定が
  // localStorage 反映前に走って誤 redirect する。
  const [state, setState] = useState<{ email: string | null; token: string | null }>(() => ({
    email: getEmail(shopSubdomain),
    token: getToken(shopSubdomain),
  }));
  useEffect(() => {
    const sync = () => setState({ email: getEmail(shopSubdomain), token: getToken(shopSubdomain) });
    sync();
    window.addEventListener("shopify_lab:auth_changed", sync);
    window.addEventListener("shopify_lab:shop_changed", sync);
    return () => {
      window.removeEventListener("shopify_lab:auth_changed", sync);
      window.removeEventListener("shopify_lab:shop_changed", sync);
    };
  }, [shopSubdomain]);
  return state;
}
