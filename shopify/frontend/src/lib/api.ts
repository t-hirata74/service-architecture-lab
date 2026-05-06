// ADR 0002: Rails backend は subdomain で tenant を解決する。dev では `X-Shop-Subdomain`
// ヘッダで明示する (TenantResolver middleware の dev fallback)。
//
// rodauth-rails は JSON+JWT mode で動いており、`/login` 成功時に Authorization
// レスポンスヘッダで Bearer token を返す。以降の API には Authorization で付ける。

import { getToken, setToken } from "./auth";

const BACKEND_URL = process.env.NEXT_PUBLIC_BACKEND_URL ?? "http://localhost:3090";

export type ApiProduct = {
  id: number;
  slug: string;
  title: string;
  description: string | null;
  status: string;
  variants?: ApiVariant[];
};

export type ApiVariant = {
  id: number;
  sku: string;
  price_cents: number;
  currency: string;
};

export type ApiCart = {
  id: number;
  status: string;
  items: Array<{
    variant_id: number;
    sku: string;
    quantity: number;
    price_cents: number;
    currency: string;
  }>;
};

export type ApiOrder = {
  id: number;
  number: number;
  status: string;
  total_cents: number;
  currency: string;
  items: Array<{ variant_id: number; quantity: number; unit_price_cents: number }>;
};

function baseHeaders(shop: string): HeadersInit {
  return { "X-Shop-Subdomain": shop, "Content-Type": "application/json", Accept: "application/json" };
}

function authHeaders(shop: string): HeadersInit {
  const tok = getToken(shop);
  return tok ? { ...baseHeaders(shop), Authorization: tok } : baseHeaders(shop);
}

async function jsonOrThrow(res: Response): Promise<unknown> {
  const txt = await res.text();
  const body: unknown = txt ? JSON.parse(txt) : null;
  if (!res.ok) {
    const err = new Error(`${res.status} ${res.statusText}`) as Error & { status: number; body: unknown };
    err.status = res.status;
    err.body = body;
    throw err;
  }
  return body;
}

// ---------- catalog (storefront) ----------

export async function listProducts(shop: string): Promise<ApiProduct[]> {
  const res = await fetch(`${BACKEND_URL}/storefront/products`, { headers: baseHeaders(shop), cache: "no-store" });
  return jsonOrThrow(res) as Promise<ApiProduct[]>;
}

export async function getProduct(shop: string, slug: string): Promise<ApiProduct> {
  const res = await fetch(`${BACKEND_URL}/storefront/products/${slug}`, { headers: baseHeaders(shop), cache: "no-store" });
  return jsonOrThrow(res) as Promise<ApiProduct>;
}

// ---------- auth ----------

export async function register(shop: string, email: string, password: string): Promise<string> {
  const headers = baseHeaders(shop);
  const cRes = await fetch(`${BACKEND_URL}/create-account`, {
    method: "POST", headers, body: JSON.stringify({ email, password })
  });
  if (!cRes.ok && cRes.status !== 409) {
    // 409 (account already exists) はそのまま login に進む
    const body = await cRes.text();
    throw new Error(`create-account failed: ${cRes.status} ${body}`);
  }
  return login(shop, email, password);
}

export async function login(shop: string, email: string, password: string): Promise<string> {
  const headers = baseHeaders(shop);
  const res = await fetch(`${BACKEND_URL}/login`, {
    method: "POST", headers, body: JSON.stringify({ email, password })
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`login failed: ${res.status} ${body}`);
  }
  const token = res.headers.get("Authorization");
  if (!token) throw new Error("login succeeded but no Authorization header returned");
  setToken(shop, token, email);
  return token;
}

// ---------- cart / checkout ----------

export async function getCart(shop: string): Promise<ApiCart> {
  const res = await fetch(`${BACKEND_URL}/storefront/cart`, { headers: authHeaders(shop), cache: "no-store" });
  return jsonOrThrow(res) as Promise<ApiCart>;
}

export async function addToCart(shop: string, variantId: number, quantity = 1): Promise<ApiCart> {
  const res = await fetch(`${BACKEND_URL}/storefront/cart/items`, {
    method: "POST", headers: authHeaders(shop), body: JSON.stringify({ variant_id: variantId, quantity })
  });
  return jsonOrThrow(res) as Promise<ApiCart>;
}

export async function removeFromCart(shop: string, variantId: number): Promise<ApiCart> {
  const res = await fetch(`${BACKEND_URL}/storefront/cart/items/${variantId}`, {
    method: "DELETE", headers: authHeaders(shop)
  });
  return jsonOrThrow(res) as Promise<ApiCart>;
}

export type CheckoutResult =
  | { ok: true; order: ApiOrder }
  | { ok: false; status: number; error: string; variantId?: number };

export async function checkout(shop: string): Promise<CheckoutResult> {
  const res = await fetch(`${BACKEND_URL}/storefront/checkout`, {
    method: "POST", headers: authHeaders(shop), body: "{}"
  });
  if (res.ok) return { ok: true, order: (await res.json()) as ApiOrder };
  const body = (await res.json().catch(() => ({}))) as { error?: string; variant_id?: number };
  return { ok: false, status: res.status, error: body.error ?? `http_${res.status}`, variantId: body.variant_id };
}
