"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";
import { login, register, storeAuth, type Role } from "@/lib/api";

export default function LoginPage() {
  const router = useRouter();
  const [mode, setMode] = useState<"login" | "register">("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [role, setRole] = useState<Role>("rider");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      const { token, user } =
        mode === "login"
          ? await login(email, password)
          : await register({
              email,
              password,
              role,
              display_name: displayName,
            });
      storeAuth(token, user);
      router.push(user.role === "driver" ? "/driver" : "/rider");
    } catch (err) {
      setError(err instanceof Error ? err.message : "failed");
    } finally {
      setLoading(false);
    }
  }

  const tab = (m: "login" | "register", label: string) => (
    <button
      type="button"
      className={`flex-1 h-9 rounded-md text-sm transition-colors ${
        mode === m
          ? "bg-[var(--accent)] text-[var(--accent-fg)]"
          : "bg-[var(--bg-subtle)] text-[var(--fg-muted)] hover:text-[var(--fg)]"
      }`}
      onClick={() => setMode(m)}
    >
      {label}
    </button>
  );

  const inputCls =
    "w-full bg-[var(--bg-elevated)] border border-[var(--border-strong)] rounded-md px-3 h-9 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)] focus-visible:border-[var(--accent)]";

  return (
    <div className="max-w-sm mx-auto bg-[var(--panel)] border border-[var(--border)] shadow-sm p-6 rounded-[var(--radius-lg)]">
      <h1 className="text-2xl font-bold tracking-tight mb-1">uber-lab</h1>
      <p className="text-sm text-[var(--fg-muted)] mb-4">
        rider なら配車要求、driver なら待機して offer を受ける。
      </p>
      <div className="flex gap-2 mb-4">
        {tab("login", "login")}
        {tab("register", "register")}
      </div>
      <form onSubmit={onSubmit} className="space-y-3">
        {mode === "register" && (
          <div>
            <span className="block text-sm mb-1 text-[var(--fg-muted)]">role</span>
            <div className="flex gap-2">
              {(["rider", "driver"] as Role[]).map((r) => (
                <button
                  key={r}
                  type="button"
                  aria-pressed={role === r}
                  className={`flex-1 h-9 rounded-md text-sm capitalize transition-colors ${
                    role === r
                      ? "bg-[var(--accent)] text-[var(--accent-fg)]"
                      : "bg-[var(--bg-subtle)] text-[var(--fg-muted)] hover:text-[var(--fg)]"
                  }`}
                  onClick={() => setRole(r)}
                >
                  {r}
                </button>
              ))}
            </div>
          </div>
        )}
        <div>
          <label htmlFor="email" className="block text-sm mb-1 text-[var(--fg-muted)]">
            email
          </label>
          <input
            id="email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className={inputCls}
            autoComplete="email"
            required
          />
        </div>
        {mode === "register" && (
          <div>
            <label
              htmlFor="display_name"
              className="block text-sm mb-1 text-[var(--fg-muted)]"
            >
              display name
            </label>
            <input
              id="display_name"
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              className={inputCls}
              autoComplete="name"
              required
            />
          </div>
        )}
        <div>
          <label
            htmlFor="password"
            className="block text-sm mb-1 text-[var(--fg-muted)]"
          >
            password
          </label>
          <input
            id="password"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className={inputCls}
            autoComplete={mode === "login" ? "current-password" : "new-password"}
            minLength={8}
            required
          />
        </div>
        {error && <p className="text-sm text-red-600">{error}</p>}
        <button
          type="submit"
          disabled={loading}
          className="w-full h-9 rounded-md bg-[var(--accent)] text-[var(--accent-fg)] hover:bg-[var(--accent-hover)] font-medium transition-colors disabled:opacity-50"
        >
          {loading ? "..." : mode === "login" ? "login" : "register"}
        </button>
      </form>
    </div>
  );
}
