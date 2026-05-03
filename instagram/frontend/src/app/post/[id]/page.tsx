"use client";

import { FormEvent, use, useEffect, useState } from "react";
import {
  ApiComment,
  ApiPost,
  createComment,
  fetchComments,
  fetchPost,
} from "@/lib/api";
import { AuthGuard } from "@/components/AuthGuard";
import { PostCard } from "@/components/PostCard";

type Params = { id: string };

export default function PostDetailPage({
  params,
}: {
  params: Promise<Params>;
}) {
  const { id } = use(params);
  return (
    <AuthGuard>
      <PostDetail id={Number(id)} />
    </AuthGuard>
  );
}

function PostDetail({ id }: { id: number }) {
  const [post, setPost] = useState<ApiPost | null>(null);
  const [comments, setComments] = useState<ApiComment[] | null>(null);
  const [body, setBody] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    Promise.all([fetchPost(id), fetchComments(id)])
      .then(([p, page]) => {
        setPost(p);
        setComments(page.results);
      })
      .catch((e) => setError((e as Error).message));
  }, [id]);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    if (!body.trim() || busy) return;
    setBusy(true);
    try {
      const c = await createComment(id, body);
      setComments((cs) => (cs ? [...cs, c] : [c]));
      setBody("");
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  if (error) return <p className="text-red-600 text-sm">{error}</p>;
  if (!post || comments === null)
    return <p className="text-sm text-black/50">loading...</p>;

  return (
    <div className="space-y-6">
      <PostCard post={post} />
      <section className="space-y-3 text-sm">
        <h2 className="text-xs uppercase tracking-wider text-black/50 dark:text-white/50">
          comments ({comments.length})
        </h2>
        {comments.length === 0 ? (
          <p className="text-black/50 dark:text-white/50">まだコメントはありません。</p>
        ) : (
          <ul className="space-y-2">
            {comments.map((c) => (
              <li key={c.id} className="border-b border-black/5 dark:border-white/5 pb-2">
                <span className="font-semibold mr-2">@{c.user.username}</span>
                <span>{c.body}</span>
                <div className="text-xs text-black/40 dark:text-white/40 mt-0.5">
                  {new Date(c.created_at).toLocaleString()}
                </div>
              </li>
            ))}
          </ul>
        )}
        <form onSubmit={onSubmit} className="flex gap-2 pt-2">
          <input
            type="text"
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder="コメントを書く…"
            className="flex-1 border rounded px-3 py-2 bg-transparent text-sm"
          />
          <button
            type="submit"
            disabled={busy || !body.trim()}
            className="px-3 py-2 rounded bg-black text-white text-xs disabled:opacity-50 dark:bg-white dark:text-black"
          >
            {busy ? "..." : "post"}
          </button>
        </form>
      </section>
    </div>
  );
}
