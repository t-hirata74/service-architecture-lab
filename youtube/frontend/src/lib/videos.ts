import { apiBaseUrl } from "./api";

export type VideoSummary = {
  id: number;
  title: string;
  status: string;
  duration_seconds: number | null;
  published_at: string | null;
  author: { id: number; name: string };
  tags: string[];
};

export type VideoDetail = VideoSummary & {
  description: string | null;
};

export type VideoListResponse = {
  items: VideoSummary[];
};

export async function fetchVideos(): Promise<VideoSummary[]> {
  const res = await fetch(`${apiBaseUrl()}/videos`, { cache: "no-store" });
  if (!res.ok) throw new Error(`videos index ${res.status}`);
  const body = (await res.json()) as VideoListResponse;
  return body.items;
}

export async function fetchVideo(id: string | number): Promise<VideoDetail | null> {
  const res = await fetch(`${apiBaseUrl()}/videos/${id}`, { cache: "no-store" });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`videos show ${res.status}`);
  return (await res.json()) as VideoDetail;
}

export type VideoStatus = "uploaded" | "transcoding" | "ready" | "published" | "failed";

export async function fetchVideoStatus(id: string | number): Promise<VideoStatus | null> {
  const res = await fetch(`${apiBaseUrl()}/videos/${id}/status`, { cache: "no-store" });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`videos status ${res.status}`);
  const body = (await res.json()) as { status: VideoStatus };
  return body.status;
}

export async function publishVideo(id: string | number): Promise<VideoDetail> {
  const res = await fetch(`${apiBaseUrl()}/videos/${id}/publish`, {
    method: "POST",
  });
  if (!res.ok) throw new Error(`videos publish ${res.status}`);
  return (await res.json()) as VideoDetail;
}

export type UploadResult = {
  id: number;
  title: string;
  status: VideoStatus;
  original_filename: string;
};

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

export function formatDuration(seconds: number | null): string {
  if (seconds == null) return "—";
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

export function formatPublishedAt(iso: string | null): string {
  if (!iso) return "未公開";
  const d = new Date(iso);
  const now = Date.now();
  const diff = (now - d.getTime()) / 1000;
  if (diff < 3600) return `${Math.floor(diff / 60)} 分前`;
  if (diff < 86400) return `${Math.floor(diff / 3600)} 時間前`;
  return `${Math.floor(diff / 86400)} 日前`;
}
