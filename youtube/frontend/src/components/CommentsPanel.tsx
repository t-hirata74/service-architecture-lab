"use client";

import { useEffect, useState } from "react";
import {
  fetchComments,
  postComment,
  type CommentNode,
} from "@/lib/comments";

function formatDate(iso: string): string {
  const d = new Date(iso);
  const diff = (Date.now() - d.getTime()) / 1000;
  if (diff < 60) return "たった今";
  if (diff < 3600) return `${Math.floor(diff / 60)} 分前`;
  if (diff < 86400) return `${Math.floor(diff / 3600)} 時間前`;
  return `${Math.floor(diff / 86400)} 日前`;
}

export default function CommentsPanel({ videoId }: { videoId: string | number }) {
  const [comments, setComments] = useState<CommentNode[]>([]);
  const [loading, setLoading] = useState(true);
  const [replyTo, setReplyTo] = useState<number | null>(null);

  async function reload() {
    const next = await fetchComments(videoId);
    setComments(next);
    setLoading(false);
  }

  useEffect(() => {
    let cancelled = false;
    fetchComments(videoId).then((next) => {
      if (cancelled) return;
      setComments(next);
      setLoading(false);
    });
    return () => {
      cancelled = true;
    };
  }, [videoId]);

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    const user_email = String(form.get("user_email") ?? "");
    const body = String(form.get("body") ?? "");
    if (!body.trim()) return;
    await postComment(videoId, {
      user_email,
      body,
      parent_id: replyTo ?? undefined,
    });
    e.currentTarget.reset();
    setReplyTo(null);
    await reload();
  }

  return (
    <section className="mt-10">
      <h2 className="mb-3 text-sm font-semibold uppercase tracking-wider opacity-70">
        コメント ({comments.length})
      </h2>

      <form onSubmit={onSubmit} className="mb-6 flex flex-col gap-2 rounded-lg bg-white/5 p-4 text-sm">
        <input
          name="user_email"
          type="email"
          required
          defaultValue="alice@example.com"
          className="rounded border border-white/10 bg-black/30 px-3 py-1.5"
        />
        <textarea
          name="body"
          rows={3}
          required
          maxLength={2000}
          placeholder={replyTo ? `返信中 (#${replyTo})` : "コメントを書く..."}
          className="rounded border border-white/10 bg-black/30 px-3 py-1.5"
        />
        <div className="flex items-center gap-3">
          <button type="submit" className="rounded bg-accent px-3 py-1 text-xs font-medium">
            {replyTo ? "返信を投稿" : "投稿"}
          </button>
          {replyTo && (
            <button
              type="button"
              onClick={() => setReplyTo(null)}
              className="text-xs underline opacity-70"
            >
              キャンセル
            </button>
          )}
        </div>
      </form>

      {loading && <p className="text-xs opacity-60">読み込み中…</p>}
      {!loading && comments.length === 0 && (
        <p className="text-xs opacity-60">まだコメントがありません。</p>
      )}

      <ul className="flex flex-col gap-4">
        {comments.map((c) => {
          const replies = c.replies ?? [];
          return (
            <li key={c.id} className="rounded-lg bg-white/5 p-3">
              <div className="text-xs opacity-70">
                {c.author.name} · {formatDate(c.created_at)}
              </div>
              <p className="mt-1 whitespace-pre-line text-sm">{c.body}</p>
              <button
                type="button"
                onClick={() => setReplyTo(c.id)}
                className="mt-1 text-[10px] uppercase tracking-wider opacity-60 hover:opacity-100"
              >
                返信
              </button>
              {replies.length > 0 && (
                <ul className="mt-3 flex flex-col gap-2 border-l border-white/10 pl-4">
                  {replies.map((r) => (
                    <li key={r.id} className="text-sm">
                      <div className="text-xs opacity-70">
                        {r.author.name} · {formatDate(r.created_at)}
                      </div>
                      <p className="whitespace-pre-line">{r.body}</p>
                    </li>
                  ))}
                </ul>
              )}
            </li>
          );
        })}
      </ul>
    </section>
  );
}
