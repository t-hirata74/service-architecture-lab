import { api } from "./api";
import type { components } from "./api-types";

export type Message = components["schemas"]["Message"];
export type MessagesPage = components["schemas"]["MessagesPage"];

export async function fetchMessages(channelId: number, before?: number, limit: number = 50): Promise<MessagesPage> {
  const params = new URLSearchParams();
  if (before !== undefined) params.set("before", String(before));
  params.set("limit", String(limit));
  const res = await api(`/channels/${channelId}/messages?${params.toString()}`);
  if (!res.ok) throw new Error("メッセージ取得に失敗しました");
  return res.json();
}

export async function postMessage(channelId: number, body: string): Promise<Message> {
  const res = await api(`/channels/${channelId}/messages`, {
    method: "POST",
    body: JSON.stringify({ body }),
  });
  if (!res.ok) throw new Error("投稿に失敗しました");
  return res.json();
}
