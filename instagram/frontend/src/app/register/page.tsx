"use client";

import { FormEvent, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { register, storeAuth } from "@/lib/api";

export default function RegisterPage() {
  const router = useRouter();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const { token, user } = await register(username, password);
      storeAuth(token, user);
      router.push("/");
    } catch (e) {
      setError((e as Error).message || "register failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-6">
      <h1 className="text-xl font-semibold">register</h1>
      <form onSubmit={onSubmit} className="space-y-3 text-sm">
        <label className="block space-y-1">
          <span className="text-xs text-black/60 dark:text-white/60">username</span>
          <input
            type="text"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            className="w-full border rounded px-3 py-2 bg-transparent"
            required
            autoComplete="username"
          />
        </label>
        <label className="block space-y-1">
          <span className="text-xs text-black/60 dark:text-white/60">password (8 文字以上)</span>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="w-full border rounded px-3 py-2 bg-transparent"
            required
            minLength={8}
            autoComplete="new-password"
          />
        </label>
        {error ? <p className="text-red-600 text-xs">{error}</p> : null}
        <button
          type="submit"
          disabled={busy}
          className="w-full px-3 py-2 rounded bg-black text-white disabled:opacity-50 dark:bg-white dark:text-black"
        >
          {busy ? "..." : "create account"}
        </button>
      </form>
      <p className="text-xs text-black/60 dark:text-white/60">
        既にアカウントがあれば <Link href="/login" className="underline">login</Link> から。
      </p>
    </div>
  );
}
