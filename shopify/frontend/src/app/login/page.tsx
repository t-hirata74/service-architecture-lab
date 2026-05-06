"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useState } from "react";
import { login, register } from "@/lib/api";
import { useShop } from "@/lib/shop";

function LoginInner() {
  const [shop] = useShop();
  const router = useRouter();
  const search = useSearchParams();
  const next = search.get("next") ?? "/";

  const [mode, setMode] = useState<"login" | "register">("register");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("passw0rd");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      if (mode === "register") {
        await register(shop, email, password);
      } else {
        await login(shop, email, password);
      }
      router.push(next);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="max-w-sm mx-auto space-y-5">
      <h2 className="text-2xl font-bold tracking-tight">
        {mode === "register" ? "register" : "login"}
        <span className="ml-2 text-xs font-normal text-zinc-500">to {shop}</span>
      </h2>

      <div className="flex gap-2 text-xs">
        <button
          type="button"
          onClick={() => setMode("register")}
          data-active={mode === "register"}
          className="px-3 py-1 rounded border border-zinc-300 data-[active=true]:bg-zinc-900 data-[active=true]:text-white data-[active=true]:border-zinc-900"
        >
          register
        </button>
        <button
          type="button"
          onClick={() => setMode("login")}
          data-active={mode === "login"}
          className="px-3 py-1 rounded border border-zinc-300 data-[active=true]:bg-zinc-900 data-[active=true]:text-white data-[active=true]:border-zinc-900"
        >
          login
        </button>
      </div>

      <form onSubmit={onSubmit} className="space-y-3">
        <label className="block text-sm">
          <span className="block text-xs text-zinc-500 mb-1">email</span>
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            data-testid="email-input"
            className="w-full border border-zinc-300 rounded px-3 py-2 text-sm bg-white"
          />
        </label>
        <label className="block text-sm">
          <span className="block text-xs text-zinc-500 mb-1">password</span>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            minLength={8}
            data-testid="password-input"
            className="w-full border border-zinc-300 rounded px-3 py-2 text-sm bg-white"
          />
        </label>

        <button
          type="submit"
          disabled={busy}
          data-testid="submit-button"
          className="w-full bg-zinc-900 text-white px-3 py-2 rounded font-medium disabled:opacity-50"
        >
          {busy ? "..." : mode === "register" ? "create account & login" : "login"}
        </button>

        {error && (
          <div className="text-xs text-red-700 bg-red-50 border border-red-200 rounded px-3 py-2" data-testid="auth-error">
            {error}
          </div>
        )}
      </form>
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense fallback={<div className="text-sm text-zinc-500">loading…</div>}>
      <LoginInner />
    </Suspense>
  );
}
