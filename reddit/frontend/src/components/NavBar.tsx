"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { type ApiUser, clearAuth, getStoredUser } from "@/lib/api";

export function NavBar() {
  const [user, setUser] = useState<ApiUser | null>(null);

  useEffect(() => {
    const sync = () => setUser(getStoredUser());
    sync();
    window.addEventListener("storage", sync);
    return () => window.removeEventListener("storage", sync);
  }, []);

  return (
    <header className="sticky top-0 z-10 border-b border-[var(--border)] bg-[var(--bg-elevated)]/80 backdrop-blur supports-[backdrop-filter]:bg-[var(--bg-elevated)]/70">
      <div className="max-w-5xl mx-auto flex items-center gap-6 px-4 h-14">
        <Link
          href="/"
          className="flex items-center gap-2 text-[var(--accent)] font-bold text-lg tracking-tight hover:opacity-90 transition-opacity"
        >
          <span aria-hidden className="size-7 rounded-full bg-[var(--accent)] grid place-items-center text-[var(--accent-fg)] text-base">r</span>
          <span>reddit (lab)</span>
        </Link>
        <nav className="flex-1 flex items-center gap-1 text-sm">
          <Link
            href="/"
            className="px-3 h-8 inline-flex items-center rounded-md text-[var(--fg-muted)] hover:text-[var(--fg)] hover:bg-[var(--bg-subtle)] transition-colors"
          >
            subreddits
          </Link>
        </nav>
        {user ? (
          <div className="flex items-center gap-2 text-sm">
            <span className="text-[var(--fg-muted)]">
              u/<span className="text-[var(--fg)] font-medium">{user.username}</span>
            </span>
            <button
              type="button"
              onClick={() => {
                clearAuth();
                window.location.href = "/";
              }}
              className="px-3 h-8 rounded-md text-[var(--fg-muted)] hover:text-[var(--fg)] hover:bg-[var(--bg-subtle)] transition-colors"
            >
              logout
            </button>
          </div>
        ) : (
          <Link
            href="/login"
            className="px-3 h-8 inline-flex items-center rounded-md bg-[var(--accent)] text-[var(--accent-fg)] text-sm font-medium hover:bg-[var(--accent-hover)] transition-colors shadow-[var(--shadow-sm)]"
          >
            login
          </Link>
        )}
      </div>
    </header>
  );
}
