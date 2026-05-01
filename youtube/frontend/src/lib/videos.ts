import { apiBaseUrl } from "./api";
import type { components } from "./api-types";

// OpenAPI スキーマ (backend/docs/openapi.yml) から生成された型を使う。
// 手書き型は撤去 — `npm run gen:api` で再生成する。
export type VideoSummary = components["schemas"]["VideoSummary"];
export type VideoDetail = components["schemas"]["VideoDetail"];
export type RecommendedVideo = components["schemas"]["RecommendedVideo"];
export type RecommendationsResponse = components["schemas"]["RecommendationsResponse"];
export type VideoStatus = components["schemas"]["VideoStatusEnum"];
export type UploadResult = components["schemas"]["UploadResponse"];

type VideoListResponse = components["schemas"]["VideoList"];
type SearchResult = components["schemas"]["SearchResult"];
type VideoStatusResponse = components["schemas"]["VideoStatus"];

export async function fetchVideos(): Promise<VideoSummary[]> {
  const res = await fetch(`${apiBaseUrl()}/videos`, { cache: "no-store" });
  if (!res.ok) throw new Error(`videos index ${res.status}`);
  const body = (await res.json()) as VideoListResponse;
  return body.items;
}

export async function searchVideos(q: string): Promise<VideoSummary[]> {
  const res = await fetch(`${apiBaseUrl()}/videos/search?q=${encodeURIComponent(q)}`, {
    cache: "no-store",
  });
  if (!res.ok) throw new Error(`videos search ${res.status}`);
  const body = (await res.json()) as SearchResult;
  return body.items;
}

export async function fetchVideo(id: string | number): Promise<VideoDetail | null> {
  const res = await fetch(`${apiBaseUrl()}/videos/${id}`, { cache: "no-store" });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`videos show ${res.status}`);
  return (await res.json()) as VideoDetail;
}

export async function fetchRecommendations(
  id: string | number,
): Promise<RecommendationsResponse> {
  const res = await fetch(`${apiBaseUrl()}/videos/${id}/recommendations`, {
    cache: "no-store",
  });
  if (!res.ok) return { items: [], degraded: true };
  return (await res.json()) as RecommendationsResponse;
}

export async function fetchVideoStatus(id: string | number): Promise<VideoStatus | null> {
  const res = await fetch(`${apiBaseUrl()}/videos/${id}/status`, { cache: "no-store" });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`videos status ${res.status}`);
  const body = (await res.json()) as VideoStatusResponse;
  return body.status;
}

export async function publishVideo(id: string | number): Promise<VideoDetail> {
  const res = await fetch(`${apiBaseUrl()}/videos/${id}/publish`, {
    method: "POST",
  });
  if (!res.ok) throw new Error(`videos publish ${res.status}`);
  return (await res.json()) as VideoDetail;
}

export async function uploadVideo(form: FormData): Promise<UploadResult> {
  const res = await fetch(`${apiBaseUrl()}/uploads`, {
    method: "POST",
    body: form,
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`upload ${res.status} ${text}`);
  }
  return (await res.json()) as UploadResult;
}

export function formatDuration(seconds: number | null | undefined): string {
  if (seconds == null) return "—";
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

export function formatPublishedAt(iso: string | null | undefined): string {
  if (!iso) return "未公開";
  const d = new Date(iso);
  const now = Date.now();
  const diff = (now - d.getTime()) / 1000;
  if (diff < 3600) return `${Math.floor(diff / 60)} 分前`;
  if (diff < 86400) return `${Math.floor(diff / 3600)} 時間前`;
  return `${Math.floor(diff / 86400)} 日前`;
}
