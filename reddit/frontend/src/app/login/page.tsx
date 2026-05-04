"use client";

import { useState } from "react";
import { login, register, storeAuth } from "@/lib/api";

export default function LoginPage() {
  const [mode, setMode] = useState<"login" | "register">("login");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      const action = mode === "login" ? login : register;
      const res = await action(username, password);
      storeAuth(res.access_token, res.user);
      window.location.href = "/";
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="max-w-sm mx-auto pt-8">
      <header className="text-center mb-6 space-y-1">
        <h1 className="text-2xl font-bold tracking-tight">
          {mode === "login" ? "Welcome back" : "Create your account"}
        </h1>
        <p className="text-sm text-[var(--fg-muted)]">
          {mode === "login"
            ? "subreddit を購読 / 投票 / コメントするにはログインが必要です。"
            : "username と password だけで始められます。"}
        </p>
      </header>
      <form
        onSubmit={submit}
        className="bg-[var(--bg-elevated)] border border-[var(--border)] rounded-[var(--radius-lg)] shadow-[var(--shadow)] p-6 space-y-4"
      >
        <div className="space-y-1.5">
          <label htmlFor="username" className="text-xs font-medium text-[var(--fg-muted)]">
            username
          </label>
          <input
            id="username"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            placeholder="alice"
            autoComplete="username"
            className="w-full px-3 h-10 border border-[var(--border-strong)] rounded-md text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)] focus-visible:border-[var(--accent)] transition-colors"
          />
        </div>
        <div className="space-y-1.5">
          <label htmlFor="password" className="text-xs font-medium text-[var(--fg-muted)]">
            password
          </label>
          <input
            id="password"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="6 文字以上"
            autoComplete="current-password"
            className="w-full px-3 h-10 border border-[var(--border-strong)] rounded-md text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)] focus-visible:border-[var(--accent)] transition-colors"
          />
        </div>
        {error && (
          <p className="text-sm text-[var(--accent)] bg-[var(--bg-subtle)] border border-[var(--border)] rounded-md px-3 py-2">
            {error}
          </p>
        )}
        <button
          type="submit"
          disabled={busy}
          className="w-full h-10 rounded-md bg-[var(--accent)] text-[var(--accent-fg)] text-sm font-medium hover:bg-[var(--accent-hover)] transition-colors shadow-[var(--shadow-sm)] disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {busy ? "..." : mode === "login" ? "login" : "register"}
        </button>
        <button
          type="button"
          onClick={() => setMode(mode === "login" ? "register" : "login")}
          className="w-full text-xs text-[var(--fg-muted)] hover:text-[var(--fg)] transition-colors"
        >
          {mode === "login" ? "create an account →" : "← back to login"}
        </button>
      </form>
    </div>
  );
}
