"use client";

import { FormEvent, useState } from "react";

export default function BookEntry() {
  const [hostId, setHostId] = useState("");
  const [slug, setSlug] = useState("");

  function onSubmit(e: FormEvent) {
    e.preventDefault();
    window.location.href = `/p/${hostId}/${slug}`;
  }

  return (
    <main className="min-h-screen bg-zinc-50 px-6 py-16">
      <div className="mx-auto max-w-md rounded-md border border-zinc-200 bg-white p-8">
        <h1 className="text-2xl font-semibold text-zinc-900">Invitee 予約ページに移動</h1>
        <p className="mt-2 text-sm text-zinc-600">
          host_id と slug を指定すると公開予約ページ <code>/p/&lt;host_id&gt;/&lt;slug&gt;</code> に遷移します。
        </p>
        <form onSubmit={onSubmit} className="mt-6 space-y-4">
          <label className="block">
            <span className="text-sm font-medium text-zinc-700">host_id</span>
            <input data-testid="host-id" type="number" required value={hostId} onChange={(e) => setHostId(e.target.value)}
                   className="mt-1 block w-full rounded border border-zinc-300 px-3 py-2 text-sm" />
          </label>
          <label className="block">
            <span className="text-sm font-medium text-zinc-700">slug</span>
            <input data-testid="slug" type="text" required value={slug} onChange={(e) => setSlug(e.target.value)}
                   className="mt-1 block w-full rounded border border-zinc-300 px-3 py-2 text-sm" />
          </label>
          <button data-testid="go" type="submit"
                  className="w-full rounded bg-emerald-600 py-2 text-sm font-semibold text-white hover:bg-emerald-700">
            予約ページへ
          </button>
        </form>
      </div>
    </main>
  );
}
