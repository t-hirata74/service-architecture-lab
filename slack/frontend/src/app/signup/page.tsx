"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { signup } from "@/lib/auth";

export default function SignupPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      await signup(email, password, displayName);
      router.push("/channels");
    } catch (err) {
      setError(err instanceof Error ? err.message : "登録に失敗しました");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main className="flex flex-1 items-center justify-center bg-[var(--bg)] px-4 py-12">
      <div className="w-full max-w-sm space-y-6">
        <header className="text-center space-y-2">
          <span
            aria-hidden
            className="inline-grid size-12 rounded-xl bg-[var(--accent)] place-items-center text-[var(--accent-fg)] text-xl font-bold shadow-[var(--shadow)]"
          >
            S
          </span>
          <h1 className="text-2xl font-bold tracking-tight">アカウント作成</h1>
          <p className="text-sm text-[var(--fg-muted)]">Slack-style chat にようこそ</p>
        </header>

        <form
          onSubmit={handleSubmit}
          className="space-y-4 rounded-[var(--radius-lg)] border border-[var(--border)] bg-[var(--bg-elevated)] p-6 shadow-[var(--shadow)]"
        >
          <div className="space-y-1.5">
            <label htmlFor="display_name" className="text-xs font-medium text-[var(--fg-muted)]">
              表示名
            </label>
            <input
              id="display_name"
              type="text"
              required
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              className="block w-full rounded-md border border-[var(--border-strong)] bg-[var(--bg-elevated)] px-3 h-10 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)] focus-visible:border-[var(--accent)] transition-colors"
            />
          </div>

          <div className="space-y-1.5">
            <label htmlFor="email" className="text-xs font-medium text-[var(--fg-muted)]">
              メールアドレス
            </label>
            <input
              id="email"
              type="email"
              required
              autoComplete="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="block w-full rounded-md border border-[var(--border-strong)] bg-[var(--bg-elevated)] px-3 h-10 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)] focus-visible:border-[var(--accent)] transition-colors"
            />
          </div>

          <div className="space-y-1.5">
            <label htmlFor="password" className="text-xs font-medium text-[var(--fg-muted)]">
              パスワード (8 文字以上)
            </label>
            <input
              id="password"
              type="password"
              required
              minLength={8}
              autoComplete="new-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="block w-full rounded-md border border-[var(--border-strong)] bg-[var(--bg-elevated)] px-3 h-10 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)] focus-visible:border-[var(--accent)] transition-colors"
            />
          </div>

          {error && (
            <p
              role="alert"
              className="rounded-md border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-700"
            >
              {error}
            </p>
          )}

          <button
            type="submit"
            disabled={submitting}
            className="w-full h-10 rounded-md bg-[var(--accent)] text-[var(--accent-fg)] text-sm font-medium hover:bg-[var(--accent-hover)] transition-colors shadow-[var(--shadow-sm)] disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {submitting ? "登録中…" : "登録する"}
          </button>

          <p className="text-center text-sm text-[var(--fg-muted)]">
            既にアカウントをお持ち？{" "}
            <Link href="/login" className="font-medium text-[var(--accent)] hover:underline">
              ログイン
            </Link>
          </p>
        </form>
      </div>
    </main>
  );
}
