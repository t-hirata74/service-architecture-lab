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
    <nav className="border-b border-black/10 dark:border-white/10 bg-background/80 sticky top-0 backdrop-blur z-10">
      <div className="max-w-2xl mx-auto flex items-center justify-between px-4 py-3 text-sm">
        <Link href="/" className="font-semibold tracking-tight">
          instagram (lab)
        </Link>
        <div className="flex items-center gap-4">
          {user ? (
            <>
              <Link href="/" className="hover:underline">timeline</Link>
              <Link href="/discover" className="hover:underline">discover</Link>
              <Link href="/post/new" className="hover:underline">post</Link>
              <Link
                href={`/users/${user.username}`}
                className="hover:underline"
              >
                @{user.username}
              </Link>
              <button
                type="button"
                onClick={onLogout}
                className="text-xs text-black/60 dark:text-white/60 hover:underline"
              >
                logout
              </button>
            </>
          ) : (
            <>
              <Link href="/login" className="hover:underline">login</Link>
              <Link href="/register" className="hover:underline">register</Link>
            </>
          )}
        </div>
      </div>
    </nav>
  );
}
