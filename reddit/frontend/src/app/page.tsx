"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import {
  type ApiSubreddit,
  type ApiUser,
  createSubreddit,
  getStoredUser,
  listSubreddits,
} from "@/lib/api";

export default function HomePage() {
  const [subs, setSubs] = useState<ApiSubreddit[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [user, setUser] = useState<ApiUser | null>(null);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");

  const refresh = async () => {
    try {
      setSubs(await listSubreddits());
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  useEffect(() => {
    setUser(getStoredUser());
    void refresh();
  }, []);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return;
    try {
      await createSubreddit(name.trim(), description.trim());
      setName("");
      setDescription("");
      await refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  };

  return (
    <div className="space-y-6">
      <header className="space-y-1">
        <h1 className="text-3xl font-bold tracking-tight">subreddits</h1>
        <p className="text-sm text-[var(--fg-muted)]">
          コミュニティを選んで投稿を読んだり、自分でコミュニティを作ったりできます。
        </p>
      </header>
      {error && (
        <div className="text-sm text-[var(--accent)] bg-[var(--bg-subtle)] border border-[var(--border)] rounded-[var(--radius-sm)] px-3 py-2">
          {error}
        </div>
      )}

      <ul className="bg-[var(--bg-elevated)] border border-[var(--border)] rounded-[var(--radius)] shadow-[var(--shadow-sm)] divide-y divide-[var(--border)] overflow-hidden">
        {subs.map((s) => (
          <li key={s.id}>
            <Link
              href={`/r/${s.name}`}
              className="flex items-baseline gap-3 px-4 py-3 hover:bg-[var(--bg-subtle)] transition-colors"
            >
              <span className="text-[var(--accent)] font-semibold">r/{s.name}</span>
              {s.description && (
                <span className="text-[var(--fg-muted)] text-sm truncate">
                  {s.description}
                </span>
              )}
            </Link>
          </li>
        ))}
        {subs.length === 0 && (
          <li className="px-4 py-12 text-center">
            <div className="text-3xl mb-2 opacity-30">📭</div>
            <p className="text-sm text-[var(--fg-subtle)]">no subreddits yet</p>
          </li>
        )}
      </ul>

      {user && (
        <form
          onSubmit={submit}
          className="bg-[var(--bg-elevated)] border border-[var(--border)] rounded-[var(--radius)] shadow-[var(--shadow-sm)] p-5 space-y-3"
        >
          <h2 className="font-semibold text-sm tracking-wide uppercase text-[var(--fg-muted)]">
            create subreddit
          </h2>
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="name (a-z, 0-9, _)"
            className="w-full px-3 h-9 border border-[var(--border-strong)] rounded-md text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)] focus-visible:border-[var(--accent)] transition-colors"
          />
          <input
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="description"
            className="w-full px-3 h-9 border border-[var(--border-strong)] rounded-md text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)] focus-visible:border-[var(--accent)] transition-colors"
          />
          <button
            type="submit"
            className="px-4 h-9 rounded-md bg-[var(--accent)] text-[var(--accent-fg)] text-sm font-medium hover:bg-[var(--accent-hover)] transition-colors shadow-[var(--shadow-sm)]"
          >
            create
          </button>
        </form>
      )}
    </div>
  );
}
