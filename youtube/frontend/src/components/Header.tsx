import Link from "next/link";
import { Suspense } from "react";
import SearchBar from "./SearchBar";

export default function Header() {
  return (
    <header className="sticky top-0 z-10 border-b border-[var(--border)] bg-[var(--bg)]/90 backdrop-blur supports-[backdrop-filter]:bg-[var(--bg)]/75">
      <div className="mx-auto flex max-w-6xl items-center justify-between gap-6 px-6 h-14">
        <Link
          href="/"
          className="flex items-center gap-2 text-base font-semibold tracking-tight hover:opacity-90 transition-opacity"
        >
          <span
            aria-hidden
            className="size-7 rounded-md bg-[var(--accent)] grid place-items-center text-[var(--accent-fg)]"
          >
            ▶
          </span>
          <span className="text-[var(--fg)]">YouTube</span>
          <span className="text-[var(--fg-muted)] text-xs">-style</span>
        </Link>
        <Suspense fallback={<div className="flex-1 max-w-md" />}>
          <SearchBar />
        </Suspense>
        <nav className="flex items-center gap-1 text-sm">
          <NavLink href="/">Home</NavLink>
          <NavLink href="/upload">Upload</NavLink>
          <NavLink href="/diagnostics">Diagnostics</NavLink>
        </nav>
      </div>
    </header>
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
