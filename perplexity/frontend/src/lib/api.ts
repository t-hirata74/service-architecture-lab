// ADR 0007: rodauth-rails JWT bearer.
// localStorage に "perplexity-jwt" があれば Authorization ヘッダで送る.
// 無ければ X-User-Id (dev/test fallback) を送る. login UI は派生タスクで実装.
export const API_BASE = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3040";
export const DEV_USER_ID = process.env.NEXT_PUBLIC_DEV_USER_ID ?? "1";
export const JWT_STORAGE_KEY = "perplexity-jwt";

function authHeaders(): Record<string, string> {
  if (typeof window !== "undefined") {
    const jwt = window.localStorage.getItem(JWT_STORAGE_KEY);
    if (jwt) return { Authorization: jwt };
  }
  return { "X-User-Id": DEV_USER_ID };
}

export type CreateQueryResponse = {
  query_id: number;
  status: string;
  stream_url: string;
};

export async function createQuery(text: string): Promise<CreateQueryResponse> {
  const res = await fetch(`${API_BASE}/queries`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...authHeaders(),
    },
    body: JSON.stringify({ text }),
  });
  if (!res.ok) {
    throw new Error(`POST /queries failed: ${res.status} ${await res.text()}`);
  }
  return res.json();
}

export type StoredCitation = {
  id: number;
  marker: string;
  position: number;
  source_id: number;
  chunk_id: number | null;
};

export type StoredAnswer = {
  id: number;
  body: string;
  status: string;
  citations: StoredCitation[];
};

export type StoredQuery = {
  id: number;
  text: string;
  status: string;
  created_at: string;
};

export type QueryDetailResponse = {
  query: StoredQuery;
  answer: StoredAnswer | null;
};

export async function getQuery(id: number): Promise<QueryDetailResponse> {
  const res = await fetch(`${API_BASE}/queries/${id}`, {
    headers: authHeaders(),
  });
  if (!res.ok) {
    throw new Error(`GET /queries/${id} failed: ${res.status}`);
  }
  return res.json();
}
