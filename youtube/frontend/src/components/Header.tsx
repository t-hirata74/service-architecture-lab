import Link from "next/link";
import { Suspense } from "react";
import SearchBar from "./SearchBar";

export default function Header() {
  return (
    <header className="border-b border-white/10 bg-black/50 backdrop-blur sticky top-0 z-10">
      <div className="mx-auto flex max-w-6xl items-center justify-between gap-6 px-6 py-3">
        <Link href="/" className="shrink-0 text-lg font-semibold tracking-tight">
          <span className="text-accent">YouTube</span>-style
        </Link>
        <Suspense fallback={<div className="flex-1 max-w-md" />}>
          <SearchBar />
        </Suspense>
        <nav className="flex items-center gap-4 text-sm opacity-80">
          <Link href="/" className="hover:opacity-100">Home</Link>
          <Link href="/upload" className="hover:opacity-100">Upload</Link>
          <Link href="/diagnostics" className="hover:opacity-100">Diagnostics</Link>
        </nav>
      </div>
    </header>
  );
}
