import { api } from "./api";
import type { components } from "./api-types";

export type Channel = components["schemas"]["Channel"];
type ChannelList = components["schemas"]["ChannelList"];
type ReadResponse = components["schemas"]["ReadResponse"];

export async function fetchChannels(): Promise<Channel[]> {
  const res = await api("/channels");
  if (!res.ok) throw new Error("チャンネル取得に失敗しました");
  const body = (await res.json()) as ChannelList;
  return body.channels;
}

export async function createChannel(name: string, kind: string = "public"): Promise<Channel> {
  const res = await api("/channels", {
    method: "POST",
    body: JSON.stringify({ name, kind }),
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(typeof body.error === "string" ? body.error : "チャンネル作成に失敗しました");
  }
  return res.json();
}

export async function markChannelRead(channelId: number, messageId: number): Promise<ReadResponse> {
  const res = await api(`/channels/${channelId}/read`, {
    method: "POST",
    body: JSON.stringify({ message_id: messageId }),
  });
  if (!res.ok) throw new Error("既読更新に失敗しました");
  return (await res.json()) as ReadResponse;
}
