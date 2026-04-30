"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { fetchMe, logout, type Me } from "@/lib/auth";

export default function MePage() {
  const router = useRouter();
  const [me, setMe] = useState<Me | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetchMe()
      .then((data) => {
        if (!cancelled) setMe(data);
      })
      .catch(() => {
        if (!cancelled) router.replace("/login");
      });
    return () => {
      cancelled = true;
    };
  }, [router]);

  async function handleLogout() {
    try {
      await logout();
      router.push("/login");
    } catch (err) {
      setError(err instanceof Error ? err.message : "ログアウトに失敗しました");
    }
  }

  if (!me) {
    return (
      <main className="flex flex-1 items-center justify-center text-sm text-slate-500">
        Loading…
      </main>
    );
  }

  return (
    <main className="flex flex-1 items-center justify-center bg-slate-50 px-4 py-12 dark:bg-slate-950">
      <section className="w-full max-w-md space-y-6 rounded-2xl border border-slate-200 bg-white p-8 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        <header className="space-y-1">
          <p className="text-xs font-medium uppercase tracking-wide text-slate-500">プロフィール</p>
          <h1 className="text-2xl font-semibold tracking-tight">{me.display_name}</h1>
          <p className="text-sm text-slate-500">{me.email}</p>
        </header>

        <dl className="grid grid-cols-3 gap-2 text-sm">
          <dt className="col-span-1 text-slate-500">ID</dt>
          <dd className="col-span-2 font-mono">{me.id}</dd>
        </dl>

        {error && (
          <p role="alert" className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700 dark:bg-red-900/40 dark:text-red-200">
            {error}
          </p>
        )}

        <button
          type="button"
          onClick={handleLogout}
          className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm font-medium transition hover:bg-slate-100 dark:border-slate-700 dark:hover:bg-slate-800"
        >
          ログアウト
        </button>
      </section>
    </main>
  );
}
