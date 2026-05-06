"use client";

import Link from "next/link";
import { useState } from "react";
import { login, signup } from "@/lib/api";

export default function SignupPage() {
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
      await signup(email, password, displayName);
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
        <h1 className="text-xl font-semibold text-zinc-900">アカウント登録</h1>

        <form className="mt-4 space-y-3" onSubmit={onSubmit}>
          <Field label="Display name" htmlFor="display_name">
            <input
              id="display_name"
              data-testid="display-name-input"
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              required
              className="w-full px-3 py-2 rounded-md border border-zinc-300 bg-white"
            />
          </Field>
          <Field label="Email" htmlFor="email">
            <input
              id="email"
              data-testid="email-input"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              className="w-full px-3 py-2 rounded-md border border-zinc-300 bg-white"
            />
          </Field>
          <Field label="Password (8+ chars)" htmlFor="password">
            <input
              id="password"
              data-testid="password-input"
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
            data-testid="submit-button"
            disabled={busy}
            className="w-full px-4 py-2 rounded-md bg-[var(--color-accent)] text-white text-sm font-medium hover:opacity-90 disabled:opacity-50"
          >
            {busy ? "Processing…" : "Create account"}
          </button>
        </form>

        <div className="mt-4 text-xs text-zinc-500 text-center">
          Already have an account?{" "}
          <Link href="/login" className="text-[var(--color-accent)] hover:underline">
            Sign in
          </Link>
        </div>
      </div>
    </div>
  );
}

function Field({ label, htmlFor, children }: { label: string; htmlFor?: string; children: React.ReactNode }) {
  return (
    <div>
      <label htmlFor={htmlFor} className="block text-xs text-zinc-500 mb-1">
        {label}
      </label>
      {children}
    </div>
  );
}
