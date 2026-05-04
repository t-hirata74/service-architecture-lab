// ADR 0002: Rails backend は subdomain で tenant を解決する。
// dev では `acme-store.localhost:3085` 等を使うが、サーバ側の Host を強制したい時は
// `X-Shop-Subdomain` ヘッダで上書きできる (TenantResolver middleware の仕様)。

const BACKEND_URL = process.env.NEXT_PUBLIC_BACKEND_URL ?? "http://localhost:3090";
const DEFAULT_SHOP = process.env.NEXT_PUBLIC_DEFAULT_SHOP ?? "acme";

export type ApiProduct = {
  id: number;
  slug: string;
  title: string;
  description: string | null;
  status: string;
};

function shopHeaders(): Record<string, string> {
  return { "X-Shop-Subdomain": DEFAULT_SHOP };
}

export async function listProducts(): Promise<ApiProduct[]> {
  const res = await fetch(`${BACKEND_URL}/storefront/products`, {
    headers: shopHeaders(),
    cache: "no-store",
  });
  if (!res.ok) throw new Error(`failed: ${res.status}`);
  return res.json();
}
