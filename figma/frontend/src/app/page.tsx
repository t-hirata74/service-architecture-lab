"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { getToken } from "@/lib/api";
import { fetchMe, logout, type Me } from "@/lib/auth";
import { createDocument, listDocuments, type DocumentSummary } from "@/lib/documents";

export default function HomePage() {
  const router = useRouter();
  const [me, setMe] = useState<Me | null>(null);
  const [docs, setDocs] = useState<DocumentSummary[]>([]);
  const [name, setName] = useState("");

  useEffect(() => {
    if (!getToken()) {
      router.replace("/login");
      return;
    }
    fetchMe()
      .then(setMe)
      .catch(() => router.replace("/login"));
    listDocuments().then(setDocs).catch(() => undefined);
  }, [router]);

  async function create(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim()) return;
    const doc = await createDocument(name.trim());
    setName("");
    router.push(`/documents/${doc.id}`);
  }

  if (!me) return <main className="p-8 text-zinc-500">読み込み中…</main>;

  return (
    <main className="mx-auto max-w-2xl px-6 py-10">
      <header className="mb-8 flex items-center justify-between">
        <h1 className="text-2xl font-semibold">figma-lab</h1>
        <div className="text-sm text-zinc-500">
          {me.name}
          <button className="ml-3 underline" onClick={() => { logout(); router.replace("/login"); }}>
            ログアウト
          </button>
        </div>
      </header>

      <form onSubmit={create} className="mb-8 flex gap-2">
        <input
          data-testid="doc-name"
          className="flex-1 rounded border border-zinc-300 px-3 py-2"
          placeholder="新しいキャンバス名"
          value={name}
          onChange={(e) => setName(e.target.value)}
        />
        <button data-testid="create-doc" className="rounded bg-violet-600 px-4 py-2 font-medium text-white" type="submit">
          作成
        </button>
      </form>

      <ul className="divide-y divide-zinc-200">
        {docs.map((d) => (
          <li key={d.id}>
            <Link href={`/documents/${d.id}`} className="flex items-center justify-between py-3 hover:bg-zinc-50">
              <span>{d.name}</span>
              <span className="text-xs text-zinc-400">{d.role} · v{d.version}</span>
            </Link>
          </li>
        ))}
        {docs.length === 0 && <li className="py-3 text-sm text-zinc-400">まだキャンバスがありません</li>}
      </ul>
    </main>
  );
}
