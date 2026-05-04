"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { ApiPost, deletePost, likePost, unlikePost } from "@/lib/api";
import { useStoredUser } from "@/lib/hooks";

export function PostCard({
  post,
  onDeleted,
}: {
  post: ApiPost;
  onDeleted?: (id: number) => void;
}) {
  const router = useRouter();
  const me = useStoredUser();
  const [liked, setLiked] = useState(post.liked_by_me);
  const [count, setCount] = useState(post.likes_count);
  const [busy, setBusy] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const isMine = me?.id === post.user.id;

  async function toggle() {
    if (busy) return;
    setBusy(true);
    const willLike = !liked;
    setLiked(willLike);
    setCount((c) => c + (willLike ? 1 : -1));
    try {
      if (willLike) await likePost(post.id);
      else await unlikePost(post.id);
    } catch {
      setLiked(!willLike);
      setCount((c) => c - (willLike ? 1 : -1));
    } finally {
      setBusy(false);
    }
  }

  async function onDelete() {
    if (deleting || !confirm("この post を削除しますか？")) return;
    setDeleting(true);
    try {
      await deletePost(post.id);
      if (onDeleted) onDeleted(post.id);
      else router.refresh();
    } catch {
      setDeleting(false);
    }
  }

  return (
    <article className="border border-[var(--border)] rounded-[var(--radius-lg)] overflow-hidden bg-[var(--bg-elevated)] shadow-[var(--shadow-sm)] hover:shadow-[var(--shadow)] transition-shadow">
      <header className="flex items-center justify-between px-4 h-12 border-b border-[var(--border)]">
        <Link
          href={`/users/${post.user.username}`}
          className="flex items-center gap-2 group"
        >
          <span
            aria-hidden
            className="size-8 rounded-full bg-gradient-to-br from-[var(--accent)] to-[var(--accent-hover)] grid place-items-center text-[var(--accent-fg)] text-xs font-bold"
          >
            {post.user.username.charAt(0).toUpperCase()}
          </span>
          <span className="font-semibold text-sm group-hover:text-[var(--accent)] transition-colors">
            @{post.user.username}
          </span>
        </Link>
        <span className="text-xs text-[var(--fg-subtle)] tabular-nums">
          {new Date(post.created_at).toLocaleString()}
        </span>
      </header>
      {post.image_url ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={post.image_url}
          alt=""
          className="w-full max-h-[600px] object-cover bg-[var(--bg-subtle)]"
        />
      ) : null}
      <div className="px-4 py-3 text-sm space-y-3">
        {post.caption ? (
          <p className="whitespace-pre-wrap leading-relaxed">{post.caption}</p>
        ) : null}
        <div className="flex items-center gap-1 -mx-2">
          <button
            type="button"
            onClick={toggle}
            className={`px-2 h-8 inline-flex items-center gap-1.5 rounded-md text-sm font-medium transition-colors ${
              liked
                ? "text-[var(--accent)] hover:bg-[var(--bg-subtle)]"
                : "text-[var(--fg-muted)] hover:text-[var(--accent)] hover:bg-[var(--bg-subtle)]"
            }`}
            aria-pressed={liked}
            disabled={busy}
          >
            <span className="text-base leading-none">{liked ? "♥" : "♡"}</span>
            <span className="tabular-nums">{count}</span>
          </button>
          <Link
            href={`/post/${post.id}`}
            className="px-2 h-8 inline-flex items-center gap-1.5 rounded-md text-sm font-medium text-[var(--fg-muted)] hover:text-[var(--fg)] hover:bg-[var(--bg-subtle)] transition-colors"
          >
            <span className="text-base leading-none">💬</span>
            <span className="tabular-nums">{post.comments_count}</span>
          </Link>
          {isMine ? (
            <button
              type="button"
              onClick={onDelete}
              disabled={deleting}
              className="ml-auto px-2 h-8 inline-flex items-center rounded-md text-xs text-[var(--fg-subtle)] hover:text-[var(--accent)] hover:bg-[var(--bg-subtle)] transition-colors disabled:opacity-50"
            >
              {deleting ? "..." : "delete"}
            </button>
          ) : null}
        </div>
      </div>
    </article>
  );
}
