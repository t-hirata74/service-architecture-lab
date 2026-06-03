"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { getStoredUser, type ApiUser } from "@/lib/api";

export default function HomePage() {
  const [user, setUser] = useState<ApiUser | null>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    setUser(getStoredUser());
    setReady(true);
  }, []);

  if (!ready) return null;

  return (
    <div className="space-y-6">
      <section>
        <h1 className="text-2xl font-bold tracking-tight">Uber lab — ride dispatch</h1>
        <p className="text-sm text-[var(--fg-muted)] mt-1 leading-relaxed">
          H3 cell index + per-cell matcher goroutine + 二者間 trip state machine を
          ローカルで再現。<span className="font-medium">rider は REST poll</span>、
          <span className="font-medium">driver は WebSocket</span> という非対称な経路を
          そのまま画面に出している。
        </p>
      </section>

      {user ? (
        <div className="bg-[var(--panel)] border border-[var(--border)] shadow-sm rounded-[var(--radius)] p-5">
          <p className="text-sm text-[var(--fg-muted)]">
            logged in as{" "}
            <span className="font-medium text-[var(--fg)]">{user.display_name}</span> (
            {user.role})
          </p>
          <Link
            href={user.role === "driver" ? "/driver" : "/rider"}
            className="mt-3 inline-flex items-center h-9 px-4 rounded-md bg-[var(--accent)] text-[var(--accent-fg)] hover:bg-[var(--accent-hover)] font-medium transition-colors"
          >
            {user.role === "driver" ? "driver console を開く" : "配車をリクエスト"}
          </Link>
        </div>
      ) : (
        <div className="grid sm:grid-cols-2 gap-4">
          <Card
            title="Rider"
            body="pickup / dropoff を選んで配車要求。GET /trips/:id を poll して matching → driver_accepted を観測する。"
          />
          <Card
            title="Driver"
            body="待機位置で go online。WebSocket で offer を受けて accept/reject。compare-and-set で二重取得を防ぐ。"
          />
          <div className="sm:col-span-2">
            <Link
              href="/login"
              className="inline-flex items-center h-9 px-4 rounded-md bg-[var(--accent)] text-[var(--accent-fg)] hover:bg-[var(--accent-hover)] font-medium transition-colors"
            >
              login / register
            </Link>
          </div>
        </div>
      )}
    </div>
  );
}

function Card({ title, body }: { title: string; body: string }) {
  return (
    <div className="bg-[var(--panel)] border border-[var(--border)] shadow-sm rounded-[var(--radius)] p-5">
      <h2 className="text-lg font-semibold">{title}</h2>
      <p className="text-sm text-[var(--fg-muted)] mt-1 leading-relaxed">{body}</p>
    </div>
  );
}
