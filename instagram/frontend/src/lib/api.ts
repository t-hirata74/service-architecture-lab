// ADR 0004: DRF TokenAuthentication, `Authorization: Token <token>`
// localStorage に "instagram-token" を保持する。

export const API_BASE = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3050";
export const TOKEN_STORAGE_KEY = "instagram-token";
export const USER_STORAGE_KEY = "instagram-user";

export type ApiUser = {
  id: number;
  username: string;
  bio: string;
  followers_count: number;
  following_count: number;
  posts_count: number;
  is_followed_by_viewer?: boolean | null;
};

export type ApiPost = {
  id: number;
  user: ApiUser;
  caption: string;
  image_url: string;
  created_at: string;
  likes_count: number;
  comments_count: number;
  liked_by_me: boolean;
};

export type Paginated<T> = {
  next: string | null;
  previous: string | null;
  results: T[];
};

export function getToken(): string | null {
  if (typeof window === "undefined") return null;
  return window.localStorage.getItem(TOKEN_STORAGE_KEY);
}

export function getStoredUser(): ApiUser | null {
  if (typeof window === "undefined") return null;
  const raw = window.localStorage.getItem(USER_STORAGE_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as ApiUser;
  } catch {
    return null;
  }
}

function _notifyAuthChange(): void {
  // W3C 仕様: native StorageEvent は他タブにしか飛ばない。
  // 同一タブの useSyncExternalStore subscriber を起こすため synthetic event を発火する。
  if (typeof window !== "undefined") {
    window.dispatchEvent(new Event("storage"));
  }
}

export function storeAuth(token: string, user: ApiUser): void {
  window.localStorage.setItem(TOKEN_STORAGE_KEY, token);
  window.localStorage.setItem(USER_STORAGE_KEY, JSON.stringify(user));
  _notifyAuthChange();
}

export function clearAuth(): void {
  window.localStorage.removeItem(TOKEN_STORAGE_KEY);
  window.localStorage.removeItem(USER_STORAGE_KEY);
  _notifyAuthChange();
}

function authHeaders(): Record<string, string> {
  const token = getToken();
  return token ? { Authorization: `Token ${token}` } : {};
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

async function apiFetch<T>(
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...authHeaders(),
      ...(init.headers ?? {}),
    },
  });
  if (res.status === 204) return undefined as T;
  const text = await res.text();
  const body = text ? JSON.parse(text) : null;
  if (!res.ok) throw new ApiError(res.status, body?.detail ?? body);
  return body as T;
}

// ─── auth ──────────────────────────────────────────────────────────────────────

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

export async function logout(): Promise<void> {
  await apiFetch("/auth/logout", { method: "POST" });
  clearAuth();
}

// ─── posts / timeline / discover ───────────────────────────────────────────────

export async function fetchTimeline(): Promise<Paginated<ApiPost>> {
  return apiFetch("/timeline");
}

export async function fetchDiscover(): Promise<{ results: ApiPost[] }> {
  return apiFetch("/discover");
}

export async function fetchUserPosts(
  username: string,
): Promise<Paginated<ApiPost>> {
  return apiFetch(`/users/${encodeURIComponent(username)}/posts`);
}

export async function fetchUser(username: string): Promise<ApiUser> {
  return apiFetch(`/users/${encodeURIComponent(username)}`);
}

export async function createPost(
  caption: string,
  image_url: string,
): Promise<ApiPost> {
  return apiFetch("/posts", {
    method: "POST",
    body: JSON.stringify({ caption, image_url }),
  });
}

export async function deletePost(id: number): Promise<void> {
  await apiFetch(`/posts/${id}`, { method: "DELETE" });
}

// ─── like ──────────────────────────────────────────────────────────────────────

export async function likePost(id: number): Promise<void> {
  await apiFetch(`/posts/${id}/like`, { method: "POST" });
}

export async function unlikePost(id: number): Promise<void> {
  await apiFetch(`/posts/${id}/like`, { method: "DELETE" });
}

// ─── follow ────────────────────────────────────────────────────────────────────

export async function follow(username: string): Promise<void> {
  await apiFetch(`/users/${encodeURIComponent(username)}/follow`, {
    method: "POST",
  });
}

export async function unfollow(username: string): Promise<void> {
  await apiFetch(`/users/${encodeURIComponent(username)}/follow`, {
    method: "DELETE",
  });
}

// ─── tags ──────────────────────────────────────────────────────────────────────

export async function suggestTags(image_url: string): Promise<{ tags: string[] }> {
  return apiFetch("/tags/suggest", {
    method: "POST",
    body: JSON.stringify({ image_url }),
  });
}
