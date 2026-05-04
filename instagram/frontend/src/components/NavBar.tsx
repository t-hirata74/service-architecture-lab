"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { clearAuth, logout } from "@/lib/api";
import { useStoredUser } from "@/lib/hooks";

export function NavBar() {
  const router = useRouter();
  const user = useStoredUser();

  async function onLogout() {
    try {
      await logout();
    } catch {
      clearAuth();
    }
    router.push("/login");
  }

  return (
    <nav className="sticky top-0 z-10 border-b border-[var(--border)] bg-[var(--bg-elevated)]/80 backdrop-blur supports-[backdrop-filter]:bg-[var(--bg-elevated)]/70">
      <div className="max-w-2xl mx-auto flex items-center justify-between px-4 h-14 text-sm">
        <Link
          href="/"
          className="flex items-center gap-2 font-semibold tracking-tight hover:opacity-90 transition-opacity"
        >
          <span
            aria-hidden
            className="size-7 rounded-md bg-gradient-to-br from-[var(--accent)] to-[var(--accent-hover)] grid place-items-center text-[var(--accent-fg)] text-base"
          >
            i
          </span>
          <span>instagram (lab)</span>
        </Link>
        <div className="flex items-center gap-1">
          {user ? (
            <>
              <NavLink href="/">timeline</NavLink>
              <NavLink href="/discover">discover</NavLink>
              <Link
                href="/post/new"
                className="px-3 h-8 inline-flex items-center rounded-md bg-[var(--accent)] text-[var(--accent-fg)] font-medium hover:bg-[var(--accent-hover)] transition-colors shadow-[var(--shadow-sm)]"
              >
                post
              </Link>
              <Link
                href={`/users/${user.username}`}
                className="px-3 h-8 inline-flex items-center rounded-md text-[var(--fg-muted)] hover:text-[var(--fg)] hover:bg-[var(--bg-subtle)] transition-colors"
              >
                @{user.username}
              </Link>
              <button
                type="button"
                onClick={onLogout}
                className="px-2 h-8 inline-flex items-center rounded-md text-xs text-[var(--fg-subtle)] hover:text-[var(--fg)] hover:bg-[var(--bg-subtle)] transition-colors"
              >
                logout
              </button>
            </>
          ) : (
            <>
              <NavLink href="/login">login</NavLink>
              <Link
                href="/register"
                className="px-3 h-8 inline-flex items-center rounded-md bg-[var(--accent)] text-[var(--accent-fg)] font-medium hover:bg-[var(--accent-hover)] transition-colors shadow-[var(--shadow-sm)]"
              >
                register
              </Link>
            </>
          )}
        </div>
      </div>
    </nav>
  );
}

function NavLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <Link
      href={href}
      className="px-3 h-8 inline-flex items-center rounded-md text-[var(--fg-muted)] hover:text-[var(--fg)] hover:bg-[var(--bg-subtle)] transition-colors"
    >
      {children}
    </Link>
  );
}
