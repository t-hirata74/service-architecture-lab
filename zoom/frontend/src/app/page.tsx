"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { getToken } from "@/lib/api";

export default function Home() {
  const [signedIn, setSignedIn] = useState<boolean | null>(null);

  useEffect(() => {
    setSignedIn(!!getToken());
  }, []);

  return (
    <div className="space-y-6">
      <section>
        <h1 className="text-3xl font-semibold tracking-tight text-zinc-900">Zoom (lab)</h1>
        <p className="text-zinc-600 mt-2 max-w-2xl">
          会議ライフサイクル状態機械 / ホスト権限の動的譲渡 / 録画→要約パイプラインの再現プロジェクト。
          WebRTC SFU は scope 外、メディア配信はモック。
        </p>
      </section>

      <section className="grid gap-3 sm:grid-cols-3">
        <Card title="ADR 0001" subtitle="State machine">
          <code className="text-xs text-zinc-600">
            scheduled → waiting_room → live → ended → recorded → summarized
          </code>
        </Card>
        <Card title="ADR 0002" subtitle="Dynamic host transfer">
          <span className="text-xs text-zinc-600">live 中の譲渡を with_lock で直列化、履歴は append-only</span>
        </Card>
        <Card title="ADR 0003" subtitle="At-least-once pipeline">
          <span className="text-xs text-zinc-600">summaries.meeting_id UNIQUE で冪等保証</span>
        </Card>
      </section>

      <section className="flex gap-3 flex-wrap">
        {signedIn === true && (
          <Link
            href="/meetings/new"
            className="inline-flex items-center px-4 py-2 rounded-md bg-[var(--color-accent)] text-white text-sm font-medium hover:opacity-90"
          >
            会議を作成
          </Link>
        )}
        {signedIn === false && (
          <Link
            href="/login"
            className="inline-flex items-center px-4 py-2 rounded-md bg-[var(--color-accent)] text-white text-sm font-medium hover:opacity-90"
          >
            サインイン / 登録
          </Link>
        )}
        <Link
          href="/join"
          className="inline-flex items-center px-4 py-2 rounded-md border border-zinc-300 text-sm text-zinc-700 hover:bg-zinc-50"
        >
          参加コードで join
        </Link>
      </section>
    </div>
  );
}

function Card({ title, subtitle, children }: { title: string; subtitle: string; children: React.ReactNode }) {
  return (
    <div className="rounded-md border border-zinc-200 bg-white p-4">
      <div className="text-xs font-medium text-zinc-400">{title}</div>
      <div className="text-sm font-semibold text-zinc-900 mt-1">{subtitle}</div>
      <div className="mt-2">{children}</div>
    </div>
  );
}
