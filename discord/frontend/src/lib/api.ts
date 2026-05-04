// REST client for Go gateway. JWT bearer auth (ADR 0004).
// localStorage に "discord-token" / "discord-user" を保持する。

export const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3060";
export const WS_BASE =
  process.env.NEXT_PUBLIC_WS_URL ?? "ws://localhost:3060/gateway";

export const TOKEN_KEY = "discord-token";
export const USER_KEY = "discord-user";

export type ApiUser = { id: number; username: string; created_at: string };
export type ApiGuild = {
  id: number;
  name: string;
  owner_id: number;
  created_at: string;
};
export type ApiChannel = {
  id: number;
  guild_id: number;
  name: string;
  created_at: string;
};
export type ApiMessage = {
  id: number;
  channel_id: number;
  user_id: number;
  body: string;
  author_username: string;
  created_at: string;
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

class ApiError extends Error {
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

export async function register(
  username: string,
  password: string,
): Promise<{ token: string; user: ApiUser }> {
  return apiFetch("/auth/register", {
    method: "POST",
    body: JSON.stringify({ username, password }),
  });
}

export async function login(
  username: string,
  password: string,
): Promise<{ token: string; user: ApiUser }> {
  return apiFetch("/auth/login", {
    method: "POST",
    body: JSON.stringify({ username, password }),
  });
}

export async function fetchMe(): Promise<{ user: ApiUser }> {
  return apiFetch("/me");
}

// ─── guilds ────────────────────────────────────────────────────────────────

export async function fetchGuilds(): Promise<{ guilds: ApiGuild[] }> {
  return apiFetch("/guilds");
}

export async function createGuild(name: string): Promise<{ guild: ApiGuild }> {
  return apiFetch("/guilds", {
    method: "POST",
    body: JSON.stringify({ name }),
  });
}

export async function joinGuild(
  guildId: number,
): Promise<{ membership: unknown }> {
  return apiFetch(`/guilds/${guildId}/members`, { method: "POST" });
}

// ─── channels ──────────────────────────────────────────────────────────────

export async function fetchChannels(
  guildId: number,
): Promise<{ channels: ApiChannel[] }> {
  return apiFetch(`/guilds/${guildId}/channels`);
}

export async function createChannel(
  guildId: number,
  name: string,
): Promise<{ channel: ApiChannel }> {
  return apiFetch(`/guilds/${guildId}/channels`, {
    method: "POST",
    body: JSON.stringify({ name }),
  });
}

// ─── messages ──────────────────────────────────────────────────────────────

export async function fetchMessages(
  channelId: number,
  before?: number,
): Promise<{ messages: ApiMessage[]; has_more: boolean; next_before?: number }> {
  const q = before ? `?before=${before}` : "";
  return apiFetch(`/channels/${channelId}/messages${q}`);
}

export async function createMessage(
  channelId: number,
  body: string,
): Promise<{ message: ApiMessage }> {
  return apiFetch(`/channels/${channelId}/messages`, {
    method: "POST",
    body: JSON.stringify({ body }),
  });
}

export async function summarizeChannel(
  channelId: number,
): Promise<{ summary: string; degraded: boolean; messages_used: number }> {
  return apiFetch(`/channels/${channelId}/summarize`, { method: "POST" });
}
