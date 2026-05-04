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
    <div className="space-y-5">
      <header className="flex items-center gap-4 pb-3 border-b border-[var(--border)]">
        <div className="size-12 rounded-full bg-[var(--accent)] grid place-items-center text-[var(--accent-fg)] text-xl font-bold shrink-0">
          {name.charAt(0).toUpperCase()}
        </div>
        <div className="flex-1 min-w-0">
          <h1 className="text-2xl font-bold tracking-tight">r/{name}</h1>
          <p className="text-xs text-[var(--fg-muted)]">community</p>
        </div>
        <div className="flex gap-1 text-sm bg-[var(--bg-elevated)] border border-[var(--border)] rounded-md p-0.5 shadow-[var(--shadow-sm)]">
          {(["hot", "new"] as const).map((s) => (
            <button
              key={s}
              type="button"
              onClick={() => setSort(s)}
              className={
                sort === s
                  ? "px-3 h-7 rounded-[5px] bg-[var(--accent)] text-[var(--accent-fg)] font-medium transition-colors"
                  : "px-3 h-7 rounded-[5px] text-[var(--fg-muted)] hover:text-[var(--fg)] hover:bg-[var(--bg-subtle)] transition-colors"
              }
            >
              {s}
            </button>
          ))}
        </div>
      </header>
      {error && (
        <div className="text-sm text-[var(--accent)] bg-[var(--bg-subtle)] border border-[var(--border)] rounded-[var(--radius-sm)] px-3 py-2">
          {error}
        </div>
      )}

      {user && (
        <form
          onSubmit={submit}
          className="bg-[var(--bg-elevated)] border border-[var(--border)] rounded-[var(--radius)] shadow-[var(--shadow-sm)] p-4 space-y-3"
        >
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="post title"
            className="w-full px-3 h-10 border border-[var(--border-strong)] rounded-md text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)] focus-visible:border-[var(--accent)] transition-colors"
          />
          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder="body (optional)"
            className="w-full px-3 py-2 border border-[var(--border-strong)] rounded-md text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)] focus-visible:border-[var(--accent)] transition-colors"
            rows={3}
          />
          <div className="flex justify-end">
            <button
              type="submit"
              className="px-4 h-9 rounded-md bg-[var(--accent)] text-[var(--accent-fg)] text-sm font-medium hover:bg-[var(--accent-hover)] transition-colors shadow-[var(--shadow-sm)]"
            >
              post
            </button>
          </div>
        </form>
      )}

      <ul className="bg-[var(--bg-elevated)] border border-[var(--border)] rounded-[var(--radius)] shadow-[var(--shadow-sm)] divide-y divide-[var(--border)] overflow-hidden">
        {posts.map((p) => (
          <li key={p.id}>
            <Link
              href={`/posts/${p.id}`}
              className="flex gap-4 px-4 py-3 hover:bg-[var(--bg-subtle)] transition-colors"
            >
              <div className="w-12 text-right shrink-0">
                <div className="text-base font-bold tabular-nums text-[var(--fg)]">
                  {p.score}
                </div>
                <div className="text-[10px] uppercase tracking-wide text-[var(--fg-subtle)]">
                  hot {p.hot_score.toFixed(1)}
                </div>
              </div>
              <div className="flex-1 min-w-0">
                <h3 className="font-semibold text-[var(--fg)] leading-snug">
                  {p.title}
                </h3>
                {p.body && (
                  <p className="text-sm text-[var(--fg-muted)] line-clamp-2 mt-1 leading-relaxed">
                    {p.body}
                  </p>
                )}
              </div>
            </Link>
          </li>
        ))}
        {posts.length === 0 && (
          <li className="px-4 py-12 text-center">
            <div className="text-3xl mb-2 opacity-30">📭</div>
            <p className="text-sm text-[var(--fg-subtle)]">no posts yet</p>
          </li>
        )}
      </ul>
    </div>
  );
}
