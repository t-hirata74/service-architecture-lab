// Phase 2: tenant switcher の選択を localStorage に持つ。
// ADR 0002: 本来は subdomain で解決するが、dev では subdomain 設定が手間なので
// X-Shop-Subdomain ヘッダで明示する (TenantResolver middleware が許す経路)。

import { useEffect, useState } from "react";

export const SHOPS = [
  { subdomain: "acme", name: "ACME Apparel" },
  { subdomain: "globex", name: "Globex Goods" },
] as const;

export type ShopSubdomain = (typeof SHOPS)[number]["subdomain"];

const KEY = "shopify_lab.shop";
const DEFAULT: ShopSubdomain = "acme";

export function getShop(): ShopSubdomain {
  if (typeof window === "undefined") return DEFAULT;
  const v = window.localStorage.getItem(KEY);
  return SHOPS.some((s) => s.subdomain === v) ? (v as ShopSubdomain) : DEFAULT;
}

export function setShop(sub: ShopSubdomain) {
  if (typeof window !== "undefined") {
    window.localStorage.setItem(KEY, sub);
    window.dispatchEvent(new CustomEvent("shopify_lab:shop_changed", { detail: sub }));
  }
}

export function useShop(): [ShopSubdomain, (s: ShopSubdomain) => void] {
  // lazy initializer で localStorage を初回 render から反映する
  // (auth.ts と同じ理由 — useEffect 反映前の判定で誤 redirect しないように)
  const [shop, setShopState] = useState<ShopSubdomain>(() => getShop());
  useEffect(() => {
    const onChange = (e: Event) => setShopState((e as CustomEvent).detail as ShopSubdomain);
    window.addEventListener("shopify_lab:shop_changed", onChange);
    return () => window.removeEventListener("shopify_lab:shop_changed", onChange);
  }, []);
  return [shop, (s) => setShop(s)];
}
