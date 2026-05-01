import { apiBaseUrl } from "./api";
import type { components } from "./api-types";

export type Comment = components["schemas"]["Comment"];
export type CommentNode = Comment;
type CommentList = components["schemas"]["CommentList"];

export async function fetchComments(videoId: string | number): Promise<CommentNode[]> {
  const res = await fetch(`${apiBaseUrl()}/videos/${videoId}/comments`, { cache: "no-store" });
  if (!res.ok) return [];
  const body = (await res.json()) as CommentList;
  return body.items;
}

export async function postComment(
  videoId: string | number,
  args: { user_email: string; body: string; parent_id?: number },
): Promise<Comment | { error: string }> {
  const res = await fetch(`${apiBaseUrl()}/videos/${videoId}/comments`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(args),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    return { error: `${res.status} ${text}` };
  }
  return (await res.json()) as Comment;
}
