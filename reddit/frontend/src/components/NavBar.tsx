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
    <header className="border-b border-[var(--border)] bg-[var(--panel)]">
      <div className="max-w-5xl mx-auto flex items-center gap-4 px-4 py-3">
        <Link href="/" className="text-[var(--accent)] font-bold text-lg">
          reddit (lab)
        </Link>
        <nav className="flex-1 text-sm">
          <Link href="/" className="text-[var(--muted)] hover:underline">
            subreddits
          </Link>
        </nav>
        {user ? (
          <div className="text-sm flex items-center gap-3">
            <span className="text-[var(--muted)]">u/{user.username}</span>
            <button
              type="button"
              onClick={() => {
                clearAuth();
                window.location.href = "/";
              }}
              className="text-[var(--accent)] hover:underline"
            >
              logout
            </button>
          </div>
        ) : (
          <Link href="/login" className="text-sm text-[var(--accent)] hover:underline">
            login
          </Link>
        )}
      </div>
    </header>
  );
}
