"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";

export default function SearchBar() {
  const router = useRouter();
  const params = useSearchParams();
  const initial = params.get("q") ?? "";
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
        className="w-full h-9 px-4 rounded-l-full border border-[var(--border-strong)] border-r-0 bg-[var(--bg-elevated)] text-sm focus:outline-none focus:ring-2 focus:ring-[var(--accent)] focus:border-[var(--accent)] transition-colors"
      />
      <button
        type="submit"
        className="h-9 px-5 rounded-r-full border border-[var(--border-strong)] bg-[var(--bg-subtle)] text-sm hover:bg-[var(--bg-elevated)] hover:border-[var(--accent)] transition-colors"
      >
        検索
      </button>
    </form>
  );
}
