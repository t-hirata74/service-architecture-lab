"use client";

import { useEffect, useState } from "react";
import { ApiPost, fetchTimeline } from "@/lib/api";
import { AuthGuard } from "@/components/AuthGuard";
import { PostCard } from "@/components/PostCard";

export default function TimelinePage() {
  return (
    <AuthGuard>
      <Timeline />
    </AuthGuard>
  );
}

function Timeline() {
  const [posts, setPosts] = useState<ApiPost[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchTimeline()
      .then((page) => setPosts(page.results))
      .catch((e) => setError((e as Error).message));
  }, []);

  if (error) return <p className="text-red-600 text-sm">{error}</p>;
  if (posts === null) return <p className="text-sm text-black/50">loading...</p>;
  if (posts.length === 0) {
    return (
      <p className="text-sm text-black/60 dark:text-white/60">
        タイムラインは空です。誰かを follow するか、最初の post を投稿してみてください。
      </p>
    );
  }
  return (
    <div className="space-y-4">
      {posts.map((p) => (
        <PostCard key={p.id} post={p} />
      ))}
    </div>
  );
}
