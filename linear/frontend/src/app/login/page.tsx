'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { login, signup } from '@/lib/api';
import { setSession } from '@/lib/session';

export default function LoginPage() {
  const router = useRouter();
  const [mode, setMode] = useState<'login' | 'signup'>('signup');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [name, setName] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError('');
    try {
      const session =
        mode === 'signup'
          ? await signup(email, password, name)
          : await login(email, password);
      setSession(session);
      router.push('/board');
    } catch {
      setError(
        mode === 'signup'
          ? '登録に失敗しました (email 重複 / パスワード 8 文字以上)'
          : 'ログインに失敗しました',
      );
    } finally {
      setBusy(false);
    }
  };

  return (
    <main className="flex min-h-screen items-center justify-center">
      <div className="w-90 rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
        <h1 className="mb-1 text-lg font-semibold">
          <span className="text-indigo-600">▲</span> linear
        </h1>
        <p className="mb-4 text-xs text-zinc-500">
          sync engine lab — Linear 風 issue tracker
        </p>
        <div className="mb-4 flex gap-1 rounded-lg bg-zinc-100 p-1 text-sm">
          {(['signup', 'login'] as const).map((m) => (
            <button
              key={m}
              type="button"
              onClick={() => setMode(m)}
              className={`flex-1 rounded-md py-1 ${
                mode === m ? 'bg-white font-medium shadow-sm' : 'text-zinc-500'
              }`}
            >
              {m === 'signup' ? '新規登録' : 'ログイン'}
            </button>
          ))}
        </div>
        <form onSubmit={(e) => void submit(e)} className="space-y-3">
          {mode === 'signup' && (
            <input
              data-testid="name"
              className="w-full rounded-md border border-zinc-300 px-3 py-2 text-sm"
              placeholder="名前"
              value={name}
              onChange={(e) => setName(e.target.value)}
              required
            />
          )}
          <input
            data-testid="email"
            type="email"
            className="w-full rounded-md border border-zinc-300 px-3 py-2 text-sm"
            placeholder="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
          />
          <input
            data-testid="password"
            type="password"
            className="w-full rounded-md border border-zinc-300 px-3 py-2 text-sm"
            placeholder="パスワード (8 文字以上)"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
          {error && <p className="text-xs text-red-600">{error}</p>}
          <button
            data-testid="submit"
            disabled={busy}
            className="w-full rounded-md bg-indigo-600 py-2 text-sm font-medium text-white hover:bg-indigo-500 disabled:opacity-50"
          >
            {mode === 'signup' ? 'ワークスペースを作成' : 'ログイン'}
          </button>
        </form>
      </div>
    </main>
  );
}
