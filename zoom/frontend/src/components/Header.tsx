"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { getToken, logout } from "@/lib/api";

export function Header() {
  const [signedIn, setSignedIn] = useState(false);

  useEffect(() => {
    setSignedIn(!!getToken());
    const onStorage = () => setSignedIn(!!getToken());
    window.addEventListener("storage", onStorage);
    return () => window.removeEventListener("storage", onStorage);
  }, []);

  return (
    <header className="border-b border-zinc-200 bg-white">
      <div className="max-w-5xl mx-auto px-4 h-14 flex items-center justify-between">
        <Link href="/" className="font-semibold tracking-tight text-zinc-900">
          <span className="text-[var(--color-accent)]">●</span> Zoom (lab)
        </Link>
        <nav className="flex items-center gap-3 text-sm">
          {signedIn ? (
            <>
              <Link href="/meetings/new" className="text-zinc-700 hover:text-zinc-900">
                New meeting
              </Link>
              <button
                type="button"
                onClick={() => {
                  logout();
                  setSignedIn(false);
                  window.location.href = "/login";
                }}
                className="text-zinc-500 hover:text-zinc-700"
              >
                Logout
              </button>
            </>
          ) : (
            <Link href="/login" className="text-[var(--color-accent)] hover:underline">
              Sign in / Sign up
            </Link>
          )}
        </nav>
      </div>
    </header>
  );
}
