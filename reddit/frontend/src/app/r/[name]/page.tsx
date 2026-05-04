"use client";

import Link from "next/link";
import { use, useEffect, useState } from "react";
import {
  type ApiPost,
  type ApiUser,
  createPost,
  getStoredUser,
  listHot,
  listNew,
} from "@/lib/api";

type Sort = "hot" | "new";

export default function SubredditPage({ params }: { params: Promise<{ name: string }> }) {
  const { name } = use(params);
  const [sort, setSort] = useState<Sort>("hot");
  const [posts, setPosts] = useState<ApiPost[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [user, setUser] = useState<ApiUser | null>(null);
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");

  const refresh = async () => {
    try {
      const fn = sort === "hot" ? listHot : listNew;
      setPosts(await fn(name));
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  useEffect(() => {
    setUser(getStoredUser());
    void refresh();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [name, sort]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim()) return;
    try {
      await createPost(name, title.trim(), body.trim());
      setTitle("");
      setBody("");
      await refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex items-baseline gap-3">
        <h1 className="text-2xl font-bold">r/{name}</h1>
        <div className="flex gap-2 text-sm">
          {(["hot", "new"] as const).map((s) => (
            <button
              key={s}
              type="button"
              onClick={() => setSort(s)}
              className={
                sort === s
                  ? "font-bold text-[var(--accent)]"
                  : "text-[var(--muted)] hover:text-[var(--foreground)]"
              }
            >
              {s}
            </button>
          ))}
        </div>
      </div>
      {error && <p className="text-red-500 text-sm">{error}</p>}

      {user && (
        <form
          onSubmit={submit}
          className="bg-[var(--panel)] border border-[var(--border)] rounded p-3 space-y-2"
        >
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="post title"
            className="w-full p-2 border border-[var(--border)] rounded text-sm"
          />
          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder="body (optional)"
            className="w-full p-2 border border-[var(--border)] rounded text-sm"
            rows={3}
          />
          <button
            type="submit"
            className="px-4 py-1 rounded bg-[var(--accent)] text-white text-sm"
          >
            post
          </button>
        </form>
      )}

      <ul className="bg-[var(--panel)] border border-[var(--border)] rounded divide-y divide-[var(--border)]">
        {posts.map((p) => (
          <li key={p.id} className="px-4 py-3 flex gap-4">
            <div className="text-[var(--muted)] text-sm w-12 text-right">
              <div className="font-bold tabular-nums">{p.score}</div>
              <div className="text-xs">hot {p.hot_score.toFixed(1)}</div>
            </div>
            <div className="flex-1">
              <Link href={`/posts/${p.id}`} className="font-bold hover:underline">
                {p.title}
              </Link>
              {p.body && (
                <p className="text-sm text-[var(--muted)] line-clamp-2 mt-1">
                  {p.body}
                </p>
              )}
            </div>
          </li>
        ))}
        {posts.length === 0 && (
          <li className="px-4 py-2 text-[var(--muted)] text-sm">no posts yet</li>
        )}
      </ul>
    </div>
  );
}
