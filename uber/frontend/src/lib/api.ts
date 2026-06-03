// REST client for the Go dispatch backend. JWT bearer auth (ADR 0004 と同じ secret)。
// localStorage に "uber-token" / "uber-user" を保持する。
//
// 役割の非対称性に注意 (backend protocol.go):
//   - rider は REST のみ。POST /trips → GET /trips/:id を poll して状態遷移を観測する。
//   - driver は WS (lib/ws.ts) で offer を受ける。REST は /me だけ。

export const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3110";
export const WS_BASE =
  process.env.NEXT_PUBLIC_WS_URL ?? "ws://localhost:3110/ws";

export const TOKEN_KEY = "uber-token";
export const USER_KEY = "uber-user";

export type Role = "rider" | "driver";

export type ApiUser = {
  id: number;
  email: string;
  role: Role;
  display_name: string;
  created_at: string;
};

// backend api/trips.go tripView と対応。null になりうる項目に注意。
export type ApiTrip = {
  id: number;
  rider_id: number;
  driver_id: number | null;
  status: string;
  pickup_lat: number;
  pickup_lng: number;
  pickup_h3_cell: string;
  dropoff_lat: number;
  dropoff_lng: number;
  fare_cents: number | null;
  canceled_reason: string | null;
  requested_at: string | null;
  matched_at: string | null;
  completed_at: string | null;
  canceled_at: string | null;
};

export function getToken(): string | null {
  if (typeof window === "undefined") return null;
  return window.localStorage.getItem(TOKEN_KEY);
}

export function getStoredUser(): ApiUser | null {
  if (typeof window === "undefined") return null;
  const raw = window.localStorage.getItem(USER_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as ApiUser;
  } catch {
    return null;
  }
}

export function storeAuth(token: string, user: ApiUser): void {
  window.localStorage.setItem(TOKEN_KEY, token);
  window.localStorage.setItem(USER_KEY, JSON.stringify(user));
  window.dispatchEvent(new Event("storage"));
}

export function clearAuth(): void {
  window.localStorage.removeItem(TOKEN_KEY);
  window.localStorage.removeItem(USER_KEY);
  window.dispatchEvent(new Event("storage"));
}

export class ApiError extends Error {
  status: number;
  detail: unknown;
  constructor(status: number, detail: unknown) {
    super(typeof detail === "string" ? detail : `HTTP ${status}`);
    this.status = status;
    this.detail = detail;
  }
}

async function apiFetch<T>(path: string, init: RequestInit = {}): Promise<T> {
  const token = getToken();
  const res = await fetch(`${API_BASE}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(init.headers ?? {}),
    },
  });
  if (
    res.status === 401 &&
    typeof window !== "undefined" &&
    !path.startsWith("/auth/")
  ) {
    if (window.localStorage.getItem(TOKEN_KEY)) {
      clearAuth();
      window.location.href = "/login";
    }
    throw new ApiError(401, "unauthorized");
  }
  if (res.status === 204) return undefined as T;
  const text = await res.text();
  const body = text ? JSON.parse(text) : null;
  if (!res.ok) throw new ApiError(res.status, body?.error ?? body);
  return body as T;
}

// ─── auth ──────────────────────────────────────────────────────────────────

export async function register(input: {
  email: string;
  password: string;
  role: Role;
  display_name: string;
}): Promise<{ token: string; user: ApiUser }> {
  return apiFetch("/auth/register", {
    method: "POST",
    body: JSON.stringify(input),
  });
}

export async function login(
  email: string,
  password: string,
): Promise<{ token: string; user: ApiUser }> {
  return apiFetch("/auth/login", {
    method: "POST",
    body: JSON.stringify({ email, password }),
  });
}

export async function fetchMe(): Promise<{ user: ApiUser }> {
  return apiFetch("/me");
}

// ─── trips (rider 経路) ───────────────────────────────────────────────────

export async function createTrip(input: {
  pickup_lat: number;
  pickup_lng: number;
  dropoff_lat: number;
  dropoff_lng: number;
}): Promise<{ trip: ApiTrip; eta_seconds: number | null }> {
  return apiFetch("/trips", {
    method: "POST",
    body: JSON.stringify(input),
  });
}

export async function fetchTrip(id: number): Promise<{ trip: ApiTrip }> {
  return apiFetch(`/trips/${id}`);
}

export async function cancelTrip(id: number): Promise<{ trip: ApiTrip }> {
  return apiFetch(`/trips/${id}/cancel`, { method: "POST" });
}

// ─── demand / surge (ai-worker 境界, degrade 安全) ─────────────────────────

export type DemandForecast = {
  h3_cell: string;
  demand_index: number;
  surge_multiplier: number;
  degraded: boolean;
};

export async function fetchDemand(
  lat: number,
  lng: number,
): Promise<DemandForecast> {
  return apiFetch(`/demand?lat=${lat}&lng=${lng}`);
}
