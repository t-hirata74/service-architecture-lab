"use client";

import { useState } from "react";
import { login, signup } from "@/lib/api";

export default function LoginPage() {
  const [mode, setMode] = useState<"login" | "signup">("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      if (mode === "signup") {
        await signup(email, password, displayName);
      }
      await login(email, password);
      window.location.href = "/";
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="max-w-md mx-auto">
      <div className="bg-white border border-zinc-200 rounded-md p-6">
        <h1 className="text-xl font-semibold text-zinc-900">
          {mode === "login" ? "サインイン" : "アカウント登録"}
        </h1>

        <div className="mt-3 inline-flex border border-zinc-200 rounded-md text-xs overflow-hidden">
          {(["login", "signup"] as const).map((m) => (
            <button
              key={m}
              type="button"
              onClick={() => setMode(m)}
              className={`px-3 py-1 ${mode === m ? "bg-[var(--color-accent)] text-white" : "bg-white text-zinc-600"}`}
            >
              {m === "login" ? "Sign in" : "Sign up"}
            </button>
          ))}
        </div>

        <form className="mt-4 space-y-3" onSubmit={onSubmit}>
          {mode === "signup" && (
            <Field label="Display name">
              <input
                value={displayName}
                onChange={(e) => setDisplayName(e.target.value)}
                required
                className="w-full px-3 py-2 rounded-md border border-zinc-300 bg-white"
              />
            </Field>
          )}
          <Field label="Email">
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              className="w-full px-3 py-2 rounded-md border border-zinc-300 bg-white"
            />
          </Field>
          <Field label="Password (8+ chars)">
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              minLength={8}
              className="w-full px-3 py-2 rounded-md border border-zinc-300 bg-white"
            />
          </Field>

          {error && <div className="text-sm text-[var(--color-danger)]">{error}</div>}

          <button
            type="submit"
            disabled={busy}
            className="w-full px-4 py-2 rounded-md bg-[var(--color-accent)] text-white text-sm font-medium hover:opacity-90 disabled:opacity-50"
          >
            {busy ? "Processing…" : mode === "login" ? "Sign in" : "Create account"}
          </button>
        </form>
      </div>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <div className="text-xs text-zinc-500 mb-1">{label}</div>
      {children}
    </label>
  );
}
