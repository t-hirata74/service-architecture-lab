"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";

export default function SearchBar() {
  const router = useRouter();
  const params = useSearchParams();
  const initial = params.get("q") ?? "";
  // controlled input。URL からの初期値は key で同期する (location 変化時に再マウント)
  const [q, setQ] = useState(initial);

  function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const trimmed = q.trim();
    if (!trimmed) return;
    router.push(`/search?q=${encodeURIComponent(trimmed)}`);
  }

  return (
    <form onSubmit={onSubmit} className="flex flex-1 max-w-md items-center">
      <input
        type="search"
        value={q}
        onChange={(e) => setQ(e.target.value)}
        placeholder="動画を検索 (タイトル / 説明 / 日本語 OK)"
        className="w-full rounded-l border border-white/10 bg-white/5 px-3 py-1.5 text-sm focus:outline-none focus:ring-1 focus:ring-accent"
      />
      <button
        type="submit"
        className="rounded-r border border-l-0 border-white/10 bg-white/10 px-3 py-1.5 text-sm hover:bg-white/15"
      >
        検索
      </button>
    </form>
  );
}
