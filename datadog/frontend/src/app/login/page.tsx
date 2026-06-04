"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { login, register } from "@/lib/auth";

export default function LoginPage() {
  const router = useRouter();
  const [mode, setMode] = useState<"login" | "register">("register");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      if (mode === "register") await register(email, password);
      else await login(email, password);
      router.push("/dashboard");
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="mx-auto mt-24 max-w-sm px-6">
      <h1 className="mb-1 text-2xl font-semibold">datadog-lab</h1>
      <p className="mb-6 text-sm text-zinc-400">メトリクス観測ダッシュボード</p>
      <div className="mb-4 flex gap-3 text-sm">
        <button className={mode === "register" ? "font-semibold text-violet-400" : "text-zinc-500"} onClick={() => setMode("register")} type="button">
          新規登録
        </button>
        <button className={mode === "login" ? "font-semibold text-violet-400" : "text-zinc-500"} onClick={() => setMode("login")} type="button">
          ログイン
        </button>
      </div>
      <form onSubmit={submit} className="flex flex-col gap-3">
        <input data-testid="email" type="email" className="rounded border border-zinc-700 bg-zinc-900 px-3 py-2" placeholder="メール" value={email} onChange={(e) => setEmail(e.target.value)} required />
        <input data-testid="password" type="password" className="rounded border border-zinc-700 bg-zinc-900 px-3 py-2" placeholder="パスワード (8文字以上)" value={password} onChange={(e) => setPassword(e.target.value)} required />
        <button data-testid="submit" className="rounded bg-violet-600 px-3 py-2 font-medium text-white disabled:opacity-50" disabled={busy} type="submit">
          {mode === "register" ? "登録して開始" : "ログイン"}
        </button>
        {error && <p className="text-sm text-red-400" data-testid="error">{error}</p>}
      </form>
    </main>
  );
}
