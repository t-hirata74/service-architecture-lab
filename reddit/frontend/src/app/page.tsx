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
      <h1 className="text-2xl font-bold">subreddits</h1>
      {error && <p className="text-red-500 text-sm">{error}</p>}

      <ul className="bg-[var(--panel)] border border-[var(--border)] rounded divide-y divide-[var(--border)]">
        {subs.map((s) => (
          <li key={s.id} className="px-4 py-2">
            <Link href={`/r/${s.name}`} className="text-[var(--accent)] font-bold">
              r/{s.name}
            </Link>
            {s.description && (
              <span className="text-[var(--muted)] text-sm ml-3">{s.description}</span>
            )}
          </li>
        ))}
        {subs.length === 0 && (
          <li className="px-4 py-2 text-[var(--muted)] text-sm">
            no subreddits yet
          </li>
        )}
      </ul>

      {user && (
        <form
          onSubmit={submit}
          className="bg-[var(--panel)] border border-[var(--border)] rounded p-4 space-y-2"
        >
          <h2 className="font-bold text-sm">create subreddit</h2>
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="name (a-z, 0-9, _)"
            className="w-full p-2 border border-[var(--border)] rounded text-sm"
          />
          <input
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="description"
            className="w-full p-2 border border-[var(--border)] rounded text-sm"
          />
          <button
            type="submit"
            className="px-4 py-1 rounded bg-[var(--accent)] text-white text-sm"
          >
            create
          </button>
        </form>
      )}
    </div>
  );
}
