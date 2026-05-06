"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";
import { login, register, storeAuth } from "@/lib/api";

export default function LoginPage() {
  const router = useRouter();
  const [mode, setMode] = useState<"login" | "register">("login");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      const fn = mode === "login" ? login : register;
      const { token, user } = await fn(username, password);
      storeAuth(token, user);
      router.push("/");
    } catch (err) {
      const msg = err instanceof Error ? err.message : "failed";
      setError(msg);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="max-w-sm mx-auto bg-[var(--panel)] p-6 rounded-lg">
      <div className="flex gap-2 mb-4 text-sm">
        <button
          type="button"
          className={`flex-1 py-2 rounded ${mode === "login" ? "bg-[var(--accent)]" : "bg-[var(--panel-2)]"}`}
          onClick={() => setMode("login")}
        >
          login
        </button>
        <button
          type="button"
          className={`flex-1 py-2 rounded ${mode === "register" ? "bg-[var(--accent)]" : "bg-[var(--panel-2)]"}`}
          onClick={() => setMode("register")}
        >
          register
        </button>
      </div>
      <form onSubmit={onSubmit} className="space-y-3">
        <div>
          <label htmlFor="username" className="block text-sm mb-1 opacity-80">username</label>
          <input
            id="username"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            className="w-full bg-[var(--panel-2)] rounded px-3 py-2"
            autoComplete="username"
            required
          />
        </div>
        <div>
          <label htmlFor="password" className="block text-sm mb-1 opacity-80">password</label>
          <input
            id="password"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="w-full bg-[var(--panel-2)] rounded px-3 py-2"
            autoComplete={mode === "login" ? "current-password" : "new-password"}
            minLength={8}
            required
          />
        </div>
        {error && <p className="text-sm text-red-400">{error}</p>}
        <button
          type="submit"
          disabled={loading}
          className="w-full bg-[var(--accent)] py-2 rounded disabled:opacity-50"
        >
          {loading ? "..." : mode === "login" ? "login" : "register"}
        </button>
      </form>
    </div>
  );
}
