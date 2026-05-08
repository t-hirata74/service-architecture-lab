// Rails backend (:3100) を叩く薄い fetch wrapper。
// JWT は localStorage に保存し、Authorization: Bearer <token> で送る。
// zoom と同形 (rodauth-rails JWT)。

export const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? "http://127.0.0.1:3100";

const TOKEN_KEY = "calendly-jwt";

export function setToken(token: string | null) {
  if (typeof window === "undefined") return;
  if (token) localStorage.setItem(TOKEN_KEY, token);
  else localStorage.removeItem(TOKEN_KEY);
}

export function getToken(): string | null {
  if (typeof window === "undefined") return null;
  return localStorage.getItem(TOKEN_KEY);
}

export async function api<T = unknown>(
  path: string,
  init: RequestInit & { skipAuth?: boolean } = {}
): Promise<T> {
  const { skipAuth, headers, ...rest } = init;
  const h: Record<string, string> = {
    "Content-Type": "application/json",
    Accept: "application/json",
    ...(headers as Record<string, string> | undefined),
  };
  if (!skipAuth) {
    const t = getToken();
    if (t) h["Authorization"] = `Bearer ${t}`;
  }

  const res = await fetch(`${API_BASE}${path}`, { ...rest, headers: h });

  if (res.status === 401 && !skipAuth) {
    setToken(null);
    if (typeof window !== "undefined" && !path.startsWith("/login") && !path.startsWith("/create-account")) {
      window.location.href = "/login";
    }
    throw new Error("unauthorized");
  }

  if (!res.ok) {
    let body: unknown = null;
    try {
      body = await res.json();
    } catch {
      body = await res.text();
    }
    throw Object.assign(new Error(`HTTP ${res.status}`), { status: res.status, body });
  }

  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

export async function signup(email: string, password: string, name: string, defaultTzId: string): Promise<string> {
  const res = await fetch(`${API_BASE}/create-account`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ email, password, name, default_tz_id: defaultTzId }),
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`signup failed (${res.status}): ${body}`);
  }
  // create-account も login と同じく Authorization ヘッダで JWT を返す
  const token = res.headers.get("Authorization");
  if (!token) throw new Error("no Authorization header on signup response");
  setToken(token);
  return token;
}

export async function login(email: string, password: string): Promise<string> {
  const res = await fetch(`${API_BASE}/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ email, password }),
  });
  if (!res.ok) throw new Error(`login failed (${res.status})`);
  const token = res.headers.get("Authorization");
  if (!token) throw new Error("no Authorization header");
  setToken(token);
  return token;
}

export function logout() {
  setToken(null);
}
