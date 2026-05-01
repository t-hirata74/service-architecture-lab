import { api } from "./api";
import type { components } from "./api-types";

export type Summary = components["schemas"]["Summary"];

export async function fetchChannelSummary(channelId: number): Promise<Summary> {
  const res = await api(`/channels/${channelId}/summary`);
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(typeof body.error === "string" ? body.error : "要約取得に失敗しました");
  }
  return res.json();
}
