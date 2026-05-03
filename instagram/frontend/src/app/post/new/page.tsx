"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";
import { createPost, suggestTags } from "@/lib/api";
import { AuthGuard } from "@/components/AuthGuard";

export default function NewPostPage() {
  return (
    <AuthGuard>
      <NewPost />
    </AuthGuard>
  );
}

function NewPost() {
  const router = useRouter();
  const [caption, setCaption] = useState("");
  const [imageUrl, setImageUrl] = useState("");
  const [tags, setTags] = useState<string[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function onSuggest() {
    if (!imageUrl) return;
    try {
      const { tags } = await suggestTags(imageUrl);
      setTags(tags);
    } catch (e) {
      setError((e as Error).message);
    }
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await createPost(caption, imageUrl);
      router.push("/");
    } catch (e) {
      setError((e as Error).message || "create failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-6">
      <h1 className="text-xl font-semibold">new post</h1>
      <form onSubmit={onSubmit} className="space-y-3 text-sm">
        <label className="block space-y-1">
          <span className="text-xs text-black/60 dark:text-white/60">image_url</span>
          <input
            type="url"
            value={imageUrl}
            onChange={(e) => setImageUrl(e.target.value)}
            placeholder="https://example.test/photo.jpg"
            className="w-full border rounded px-3 py-2 bg-transparent"
          />
        </label>
        <button
          type="button"
          onClick={onSuggest}
          disabled={!imageUrl}
          className="text-xs px-3 py-1.5 rounded border disabled:opacity-50"
        >
          ai-worker でタグを提案
        </button>
        {tags.length > 0 ? (
          <div className="text-xs text-black/60 dark:text-white/60 flex flex-wrap gap-2">
            {tags.map((t) => (
              <span key={t} className="px-2 py-0.5 border rounded">
                #{t}
              </span>
            ))}
          </div>
        ) : null}
        <label className="block space-y-1">
          <span className="text-xs text-black/60 dark:text-white/60">caption</span>
          <textarea
            value={caption}
            onChange={(e) => setCaption(e.target.value)}
            rows={4}
            className="w-full border rounded px-3 py-2 bg-transparent"
          />
        </label>
        {error ? <p className="text-red-600 text-xs">{error}</p> : null}
        <button
          type="submit"
          disabled={busy}
          className="w-full px-3 py-2 rounded bg-black text-white disabled:opacity-50 dark:bg-white dark:text-black"
        >
          {busy ? "..." : "post"}
        </button>
      </form>
    </div>
  );
}
