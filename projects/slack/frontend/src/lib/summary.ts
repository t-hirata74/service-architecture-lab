import { api } from "./api";

export type Summary = {
  channel_name: string;
  message_count: number;
  participants: string[];
  summary: string;
};

export async function fetchChannelSummary(channelId: number): Promise<Summary> {
  const res = await api(`/channels/${channelId}/summary`);
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(typeof body.error === "string" ? body.error : "要約取得に失敗しました");
  }
  return res.json();
}
