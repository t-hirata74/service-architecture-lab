"use client";

import { use, useEffect, useState } from "react";
import {
  type ApiComment,
  type ApiPost,
  type ApiUser,
  createComment,
  getPost,
  getStoredUser,
  listComments,
  summarizePost,
  votePost,
} from "@/lib/api";
import { CommentTree } from "@/components/CommentTree";
import { VoteButtons } from "@/components/VoteButtons";

export default function PostPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const postId = Number(id);
  const [post, setPost] = useState<ApiPost | null>(null);
  const [comments, setComments] = useState<ApiComment[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [user, setUser] = useState<ApiUser | null>(null);
  const [body, setBody] = useState("");
  const [summary, setSummary] = useState<{
    summary?: string;
    keywords?: string[];
    degraded: boolean;
    reason?: string;
  } | null>(null);

  const refresh = async () => {
    try {
      const [p, cs] = await Promise.all([getPost(postId), listComments(postId)]);
      setPost(p);
      setComments(cs);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  useEffect(() => {
    setUser(getStoredUser());
    void refresh();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [postId]);

  const submitTopLevel = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!body.trim()) return;
    try {
      await createComment(postId, body.trim(), null);
      setBody("");
      await refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  };

  const askSummary = async () => {
    setSummary(await summarizePost(postId));
  };

  if (!post) {
    return <p className="text-[var(--muted)]">{error ?? "loading..."}</p>;
  }

  return (
    <div className="space-y-4">
      <div className="bg-[var(--panel)] border border-[var(--border)] rounded p-4 flex gap-4">
        <VoteButtons
          initialScore={post.score}
          onVote={async (v) => await votePost(post.id, v)}
        />
        <div className="flex-1">
          <h1 className="text-xl font-bold">{post.title}</h1>
          {post.body && <p className="mt-2 whitespace-pre-wrap">{post.body}</p>}
          <div className="mt-2 text-xs text-[var(--muted)]">
            hot_score {post.hot_score.toFixed(4)} · created {post.created_at}
          </div>
          <button
            type="button"
            onClick={askSummary}
            className="mt-2 text-xs text-[var(--accent)] hover:underline"
          >
            ask ai-worker for TL;DR
          </button>
          {summary && (
            <div className="mt-2 text-xs bg-[var(--panel-2)] border border-[var(--border)] rounded p-2">
              {summary.degraded ? (
                <span className="text-[var(--muted)]">
                  ai-worker degraded ({summary.reason ?? "unknown"})
                </span>
              ) : (
                <>
                  <div>{summary.summary}</div>
                  <div className="text-[var(--muted)] mt-1">
                    keywords: {summary.keywords?.join(", ")}
                  </div>
                </>
              )}
            </div>
          )}
        </div>
      </div>

      {error && <p className="text-red-500 text-sm">{error}</p>}

      {user ? (
        <form
          onSubmit={submitTopLevel}
          className="bg-[var(--panel)] border border-[var(--border)] rounded p-3 space-y-2"
        >
          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder="add a comment"
            className="w-full p-2 border border-[var(--border)] rounded text-sm"
            rows={3}
          />
          <button
            type="submit"
            className="px-4 py-1 rounded bg-[var(--accent)] text-white text-sm"
          >
            comment
          </button>
        </form>
      ) : (
        <p className="text-sm text-[var(--muted)]">login to comment / vote</p>
      )}

      <h2 className="font-bold">comments ({comments.length})</h2>
      <CommentTree
        postId={postId}
        comments={comments}
        onChange={refresh}
        authenticated={!!user}
      />
    </div>
  );
}
