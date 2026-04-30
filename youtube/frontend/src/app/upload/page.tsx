"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Header from "@/components/Header";
import { uploadVideo } from "@/lib/videos";

export default function UploadPage() {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    const form = new FormData(e.currentTarget);
    try {
      const result = await uploadVideo(form);
      router.push(`/videos/${result.id}/processing`);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      setSubmitting(false);
    }
  }

  return (
    <>
      <Header />
      <main className="mx-auto w-full max-w-xl flex-1 px-6 py-8">
        <h1 className="mb-2 text-2xl font-semibold">動画をアップロード</h1>
        <p className="mb-6 text-sm opacity-70">
          uploaded → transcoding → ready の状態機械を観察するためのデモ。
          Phase 3 では認証なしで誰でも投稿できる。
        </p>

        <form onSubmit={onSubmit} className="flex flex-col gap-4">
          <label className="flex flex-col gap-1 text-sm">
            <span>投稿者メール</span>
            <input
              name="user_email"
              type="email"
              required
              defaultValue="alice@example.com"
              className="rounded border border-white/10 bg-white/5 px-3 py-2"
            />
            <span className="text-xs opacity-50">
              alice@example.com / bob@example.com / carol@example.com (seeds)
            </span>
          </label>

          <label className="flex flex-col gap-1 text-sm">
            <span>タイトル</span>
            <input
              name="title"
              type="text"
              required
              maxLength={200}
              className="rounded border border-white/10 bg-white/5 px-3 py-2"
            />
          </label>

          <label className="flex flex-col gap-1 text-sm">
            <span>説明</span>
            <textarea
              name="description"
              rows={4}
              className="rounded border border-white/10 bg-white/5 px-3 py-2"
            />
          </label>

          <label className="flex flex-col gap-1 text-sm">
            <span>動画ファイル</span>
            <input
              name="file"
              type="file"
              required
              accept="video/*,application/octet-stream"
              className="rounded border border-white/10 bg-white/5 px-3 py-2 text-sm file:mr-3 file:rounded file:border-0 file:bg-white/10 file:px-3 file:py-1.5"
            />
            <span className="text-xs opacity-50">
              実コーデックは扱わないので任意のバイト列で OK
            </span>
          </label>

          {error && (
            <div className="rounded border border-red-500/40 bg-red-500/10 p-3 text-sm">
              {error}
            </div>
          )}

          <button
            type="submit"
            disabled={submitting}
            className="rounded bg-accent px-4 py-2 text-sm font-medium disabled:opacity-50"
          >
            {submitting ? "アップロード中…" : "アップロード"}
          </button>
        </form>
      </main>
    </>
  );
}
