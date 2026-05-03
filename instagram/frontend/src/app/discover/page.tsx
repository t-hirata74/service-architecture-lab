"use client";

import { useEffect, useState } from "react";
import { ApiPost, fetchDiscover } from "@/lib/api";
import { AuthGuard } from "@/components/AuthGuard";
import { PostCard } from "@/components/PostCard";

export default function DiscoverPage() {
  return (
    <AuthGuard>
      <Discover />
    </AuthGuard>
  );
}

function Discover() {
  const [posts, setPosts] = useState<ApiPost[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchDiscover()
      .then((res) => setPosts(res.results))
      .catch((e) => setError((e as Error).message));
  }, []);

  if (error) return <p className="text-red-600 text-sm">{error}</p>;
  if (posts === null) return <p className="text-sm text-black/50">loading...</p>;
  if (posts.length === 0) {
    return (
      <p className="text-sm text-black/60 dark:text-white/60">
        ai-worker からの推薦は今は空です (フォロー外の最新投稿があれば出ます)。
      </p>
    );
  }
  return (
    <div className="space-y-4">
      <h1 className="text-lg font-semibold">discover</h1>
      <p className="text-xs text-black/50 dark:text-white/50">
        ai-worker /recommend が返したフォロー外ユーザの直近投稿
      </p>
      {posts.map((p) => (
        <PostCard key={p.id} post={p} />
      ))}
    </div>
  );
}
