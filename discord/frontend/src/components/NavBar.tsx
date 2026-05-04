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
    <header className="bg-[var(--panel)] border-b border-black/40">
      <div className="max-w-5xl mx-auto px-4 py-3 flex items-center gap-4">
        <Link href="/" className="font-semibold">
          discord-lab
        </Link>
        <div className="flex-1" />
        {user ? (
          <>
            <span className="text-sm opacity-80">@{user.username}</span>
            <button
              type="button"
              onClick={() => {
                clearAuth();
                router.push("/login");
              }}
              className="text-sm px-3 py-1 rounded bg-[var(--panel-2)] hover:bg-black/40"
            >
              logout
            </button>
          </>
        ) : (
          <Link
            href="/login"
            className="text-sm px-3 py-1 rounded bg-[var(--accent)] hover:opacity-90"
          >
            login
          </Link>
        )}
      </div>
    </header>
  );
}
