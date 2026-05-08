"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";
import { login } from "../../lib/api";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      await login(email, password);
      router.push("/dashboard");
    } catch (err: unknown) {
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main className="min-h-screen bg-zinc-50 px-6 py-16">
      <div className="mx-auto max-w-md rounded-md border border-zinc-200 bg-white p-8">
        <h1 className="text-2xl font-semibold text-zinc-900">Host ログイン</h1>
        <form onSubmit={onSubmit} className="mt-6 space-y-4">
          <label className="block">
            <span className="text-sm font-medium text-zinc-700">メールアドレス</span>
            <input data-testid="email-input" type="email" required value={email} onChange={(e) => setEmail(e.target.value)}
                   className="mt-1 block w-full rounded border border-zinc-300 px-3 py-2 text-sm" />
          </label>
          <label className="block">
            <span className="text-sm font-medium text-zinc-700">パスワード</span>
            <input data-testid="password-input" type="password" required value={password} onChange={(e) => setPassword(e.target.value)}
                   className="mt-1 block w-full rounded border border-zinc-300 px-3 py-2 text-sm" />
          </label>
          {error && <p data-testid="error" className="text-sm text-rose-600">{error}</p>}
          <button data-testid="submit-button" type="submit" disabled={submitting}
                  className="w-full rounded bg-emerald-600 py-2 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-50">
            {submitting ? "ログイン中…" : "ログイン"}
          </button>
        </form>
      </div>
    </main>
  );
}
