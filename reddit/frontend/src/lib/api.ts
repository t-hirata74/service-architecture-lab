// REST client for FastAPI backend. JWT bearer auth (ADR 0004).
// 匿名閲覧 (anonymous read) は token なしで成立する。

export const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3070";

export const TOKEN_KEY = "reddit-token";
export const USER_KEY = "reddit-user";

export type ApiUser = { id: number; username: string; created_at: string };
export type ApiSubreddit = {
  id: number;
  name: string;
  description: string;
  created_by: number;
  created_at: string;
};
export type ApiPost = {
  id: number;
  subreddit_id: number;
  user_id: number;
  title: string;
  body: string;
  score: number;
  hot_score: number;
  created_at: string;
};
export type ApiComment = {
  id: number;
  post_id: number;
  parent_id: number | null;
  path: string;
  depth: number;
  user_id: number;
  body: string;
  score: number;
  deleted_at: string | null;
  created_at: string;
};
export type ApiVote = { target_id: number; score: number; user_value: number };

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
  if (!res.ok) throw new ApiError(res.status, body?.detail ?? body);
  return body as T;
}

// ─── auth ──────────────────────────────────────────────────────────────────

type AuthResponse = { access_token: string; token_type: string; user: ApiUser };

export async function register(username: string, password: string): Promise<AuthResponse> {
  return apiFetch("/auth/register", {
    method: "POST",
    body: JSON.stringify({ username, password }),
  });
}

export async function login(username: string, password: string): Promise<AuthResponse> {
  return apiFetch("/auth/login", {
    method: "POST",
    body: JSON.stringify({ username, password }),
  });
}

// ─── subreddits ────────────────────────────────────────────────────────────

export async function listSubreddits(): Promise<ApiSubreddit[]> {
  return apiFetch("/r");
}

export async function createSubreddit(
  name: string,
  description: string,
): Promise<ApiSubreddit> {
  return apiFetch("/r", {
    method: "POST",
    body: JSON.stringify({ name, description }),
  });
}

export async function getSubreddit(name: string): Promise<ApiSubreddit> {
  return apiFetch(`/r/${name}`);
}

export async function listHot(name: string): Promise<ApiPost[]> {
  return apiFetch(`/r/${name}/hot`);
}

export async function listNew(name: string): Promise<ApiPost[]> {
  return apiFetch(`/r/${name}/new`);
}

// ─── posts ────────────────────────────────────────────────────────────────

export async function createPost(
  subName: string,
  title: string,
  body: string,
): Promise<ApiPost> {
  return apiFetch(`/r/${subName}/posts`, {
    method: "POST",
    body: JSON.stringify({ title, body }),
  });
}

export async function getPost(postId: number): Promise<ApiPost> {
  return apiFetch(`/posts/${postId}`);
}

export async function summarizePost(
  postId: number,
): Promise<{ summary?: string; keywords?: string[]; degraded: boolean; reason?: string }> {
  return apiFetch(`/posts/${postId}/summarize`, { method: "POST" });
}

// ─── comments ─────────────────────────────────────────────────────────────

export async function listComments(postId: number): Promise<ApiComment[]> {
  return apiFetch(`/posts/${postId}/comments`);
}

export async function createComment(
  postId: number,
  body: string,
  parentId: number | null,
): Promise<ApiComment> {
  return apiFetch(`/posts/${postId}/comments`, {
    method: "POST",
    body: JSON.stringify({ body, parent_id: parentId }),
  });
}

export async function deleteComment(commentId: number): Promise<ApiComment> {
  return apiFetch(`/comments/${commentId}`, { method: "DELETE" });
}

// ─── votes ────────────────────────────────────────────────────────────────

export async function votePost(postId: number, value: -1 | 0 | 1): Promise<ApiVote> {
  return apiFetch(`/posts/${postId}/vote`, {
    method: "POST",
    body: JSON.stringify({ value }),
  });
}

export async function voteComment(commentId: number, value: -1 | 0 | 1): Promise<ApiVote> {
  return apiFetch(`/comments/${commentId}/vote`, {
    method: "POST",
    body: JSON.stringify({ value }),
  });
}
