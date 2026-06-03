"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { clearAuth, getStoredUser, type ApiUser } from "@/lib/api";

export function NavBar() {
  const [user, setUser] = useState<ApiUser | null>(null);
  const router = useRouter();

  useEffect(() => {
    const sync = () => setUser(getStoredUser());
    sync();
    window.addEventListener("storage", sync);
    return () => window.removeEventListener("storage", sync);
  }, []);

  return (
    <header className="bg-[var(--panel)] border-b border-[var(--border)]">
      <div className="max-w-5xl mx-auto px-4 py-3 flex items-center gap-4">
        <Link href="/" className="font-semibold tracking-tight">
          uber-lab
        </Link>
        <div className="flex-1" />
        {user ? (
          <>
            <span className="text-sm text-[var(--fg-muted)]">
              {user.display_name}
              <span className="ml-1.5 inline-block rounded bg-[var(--bg-subtle)] px-1.5 py-0.5 text-xs uppercase tracking-wide">
                {user.role}
              </span>
            </span>
            <button
              type="button"
              onClick={() => {
                clearAuth();
                router.push("/login");
              }}
              className="text-sm px-3 h-9 rounded-md text-[var(--fg-muted)] hover:bg-[var(--bg-subtle)] hover:text-[var(--fg)] transition-colors"
            >
              logout
            </button>
          </>
        ) : (
          <Link
            href="/login"
            className="text-sm px-4 h-9 inline-flex items-center rounded-md bg-[var(--accent)] text-[var(--accent-fg)] hover:bg-[var(--accent-hover)] transition-colors"
          >
            login
          </Link>
        )}
      </div>
    </header>
  );
}
