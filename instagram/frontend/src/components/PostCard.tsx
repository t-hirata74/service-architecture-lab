"use client";

import Link from "next/link";
import { useState } from "react";
import { ApiPost, likePost, unlikePost } from "@/lib/api";

export function PostCard({ post }: { post: ApiPost }) {
  const [liked, setLiked] = useState(post.liked_by_me);
  const [count, setCount] = useState(post.likes_count);
  const [busy, setBusy] = useState(false);

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
      // revert on failure
      setLiked(!willLike);
      setCount((c) => c - (willLike ? 1 : -1));
    } finally {
      setBusy(false);
    }
  }

  return (
    <article className="border border-black/10 dark:border-white/10 rounded-lg overflow-hidden bg-background">
      <header className="flex items-center justify-between px-4 py-2 text-sm">
        <Link
          href={`/users/${post.user.username}`}
          className="font-semibold hover:underline"
        >
          @{post.user.username}
        </Link>
        <span className="text-xs text-black/50 dark:text-white/50">
          {new Date(post.created_at).toLocaleString()}
        </span>
      </header>
      {post.image_url ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={post.image_url}
          alt=""
          className="w-full max-h-[600px] object-cover bg-black/5"
        />
      ) : null}
      <div className="px-4 py-3 text-sm space-y-2">
        {post.caption ? <p className="whitespace-pre-wrap">{post.caption}</p> : null}
        <div className="flex items-center gap-4 text-xs text-black/60 dark:text-white/60">
          <button
            type="button"
            onClick={toggle}
            className={`hover:underline ${liked ? "text-pink-600 dark:text-pink-400" : ""}`}
            aria-pressed={liked}
            disabled={busy}
          >
            {liked ? "♥" : "♡"} {count}
          </button>
          <span>💬 {post.comments_count}</span>
        </div>
      </div>
    </article>
  );
}
