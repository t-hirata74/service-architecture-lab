import { apiBaseUrl } from "./api";

export type CommentReply = {
  id: number;
  body: string;
  created_at: string;
  author: { id: number; name: string };
  parent_id: number | null;
};

export type CommentNode = CommentReply & {
  replies: CommentReply[];
};

export type CommentsResponse = {
  items: CommentNode[];
};

export async function fetchComments(videoId: string | number): Promise<CommentNode[]> {
  const res = await fetch(`${apiBaseUrl()}/videos/${videoId}/comments`, { cache: "no-store" });
  if (!res.ok) return [];
  const body = (await res.json()) as CommentsResponse;
  return body.items;
}

export async function postComment(
  videoId: string | number,
  args: { user_email: string; body: string; parent_id?: number },
): Promise<CommentNode | { error: string }> {
  const res = await fetch(`${apiBaseUrl()}/videos/${videoId}/comments`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(args),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    return { error: `${res.status} ${text}` };
  }
  return (await res.json()) as CommentNode;
}
