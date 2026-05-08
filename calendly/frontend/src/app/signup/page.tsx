"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";
import { signup } from "../../lib/api";

export default function SignupPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [name, setName] = useState("");
  const [tz, setTz] = useState("Asia/Tokyo");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      await signup(email, password, name, tz);
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
        <h1 className="text-2xl font-semibold text-zinc-900">Host サインアップ</h1>
        <form onSubmit={onSubmit} className="mt-6 space-y-4" data-testid="signup-form">
          <Field label="メールアドレス">
            <input data-testid="email-input" type="email" required value={email} onChange={(e) => setEmail(e.target.value)}
                   className="block w-full rounded border border-zinc-300 px-3 py-2 text-sm" />
          </Field>
          <Field label="パスワード (8 文字以上)">
            <input data-testid="password-input" type="password" required minLength={8} value={password} onChange={(e) => setPassword(e.target.value)}
                   className="block w-full rounded border border-zinc-300 px-3 py-2 text-sm" />
          </Field>
          <Field label="表示名">
            <input data-testid="name-input" type="text" required value={name} onChange={(e) => setName(e.target.value)}
                   className="block w-full rounded border border-zinc-300 px-3 py-2 text-sm" />
          </Field>
          <Field label="デフォルト TZ (IANA)">
            <input data-testid="tz-input" type="text" required value={tz} onChange={(e) => setTz(e.target.value)}
                   className="block w-full rounded border border-zinc-300 px-3 py-2 text-sm" />
          </Field>
          {error && <p data-testid="error" className="text-sm text-rose-600">{error}</p>}
          <button data-testid="submit-button" type="submit" disabled={submitting}
                  className="w-full rounded bg-emerald-600 py-2 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-50">
            {submitting ? "登録中…" : "登録"}
          </button>
        </form>
      </div>
    </main>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="text-sm font-medium text-zinc-700">{label}</span>
      <div className="mt-1">{children}</div>
    </label>
  );
}
