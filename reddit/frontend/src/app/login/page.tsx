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
    <div className="max-w-md mx-auto">
      <h1 className="text-2xl font-bold mb-4">{mode === "login" ? "login" : "register"}</h1>
      <form
        onSubmit={submit}
        className="bg-[var(--panel)] border border-[var(--border)] rounded p-4 space-y-3"
      >
        <input
          value={username}
          onChange={(e) => setUsername(e.target.value)}
          placeholder="username"
          autoComplete="username"
          className="w-full p-2 border border-[var(--border)] rounded text-sm"
        />
        <input
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder="password (≥6)"
          autoComplete="current-password"
          className="w-full p-2 border border-[var(--border)] rounded text-sm"
        />
        {error && <p className="text-red-500 text-sm">{error}</p>}
        <button
          type="submit"
          disabled={busy}
          className="w-full py-2 rounded bg-[var(--accent)] text-white text-sm disabled:opacity-50"
        >
          {busy ? "..." : mode === "login" ? "login" : "register"}
        </button>
        <button
          type="button"
          onClick={() => setMode(mode === "login" ? "register" : "login")}
          className="w-full text-xs text-[var(--muted)] hover:underline"
        >
          {mode === "login" ? "create an account →" : "← back to login"}
        </button>
      </form>
    </div>
  );
}
