"use client";

import { FormEvent, useEffect, useState } from "react";
import Link from "next/link";
import { AuthGuard } from "@/components/AuthGuard";
import {
  ApiGuild,
  createGuild,
  fetchGuilds,
  joinGuild,
} from "@/lib/api";

function GuildList() {
  const [guilds, setGuilds] = useState<ApiGuild[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [joinId, setJoinId] = useState("");

  async function refresh() {
    setLoading(true);
    try {
      const { guilds } = await fetchGuilds();
      setGuilds(guilds);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    refresh();
  }, []);

  async function onCreate(e: FormEvent) {
    e.preventDefault();
    if (!name.trim()) return;
    try {
      await createGuild(name.trim());
      setName("");
      await refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    }
  }

  async function onJoin(e: FormEvent) {
    e.preventDefault();
    const id = Number(joinId);
    if (!Number.isFinite(id) || id <= 0) return;
    try {
      await joinGuild(id);
      setJoinId("");
      await refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    }
  }

  return (
    <div className="space-y-6">
      <section className="bg-[var(--panel)] rounded-lg p-4">
        <h2 className="font-semibold mb-3">your guilds</h2>
        {loading && <p className="text-sm opacity-70">loading…</p>}
        {error && <p className="text-sm text-red-400">{error}</p>}
        {!loading && guilds.length === 0 && (
          <p className="text-sm opacity-70">
            no guilds yet — create one or join by id
          </p>
        )}
        <ul className="divide-y divide-black/30">
          {guilds.map((g) => (
            <li key={g.id} className="py-2 flex items-center gap-2">
              <span className="font-mono text-xs opacity-60">#{g.id}</span>
              <Link
                href={`/guilds/${g.id}`}
                className="flex-1 hover:underline"
              >
                {g.name}
              </Link>
            </li>
          ))}
        </ul>
      </section>

      <section className="bg-[var(--panel)] rounded-lg p-4">
        <h3 className="font-semibold mb-3">create guild</h3>
        <form onSubmit={onCreate} className="flex gap-2">
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="guild name"
            className="flex-1 bg-[var(--panel-2)] rounded px-3 py-2"
          />
          <button className="bg-[var(--accent)] rounded px-4">create</button>
        </form>
      </section>

      <section className="bg-[var(--panel)] rounded-lg p-4">
        <h3 className="font-semibold mb-3">join existing guild by id</h3>
        <form onSubmit={onJoin} className="flex gap-2">
          <input
            value={joinId}
            onChange={(e) => setJoinId(e.target.value)}
            placeholder="123"
            className="flex-1 bg-[var(--panel-2)] rounded px-3 py-2"
          />
          <button className="bg-[var(--panel-2)] rounded px-4">join</button>
        </form>
      </section>
    </div>
  );
}

export default function Home() {
  return (
    <AuthGuard>
      <GuildList />
    </AuthGuard>
  );
}
