"use client";

import { use, useEffect, useState } from "react";
import {
  ApiPost,
  ApiUser,
  fetchUser,
  fetchUserPosts,
  follow,
  getStoredUser,
  unfollow,
} from "@/lib/api";
import { AuthGuard } from "@/components/AuthGuard";
import { PostCard } from "@/components/PostCard";

type Params = { username: string };

export default function ProfilePage({
  params,
}: {
  params: Promise<Params>;
}) {
  const { username } = use(params);
  return (
    <AuthGuard>
      <Profile username={username} />
    </AuthGuard>
  );
}

function Profile({ username }: { username: string }) {
  const [user, setUser] = useState<ApiUser | null>(null);
  const [posts, setPosts] = useState<ApiPost[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [following, setFollowing] = useState(false);
  const [busy, setBusy] = useState(false);

  const me = getStoredUser();
  const isMe = me?.username === username;

  useEffect(() => {
    Promise.all([fetchUser(username), fetchUserPosts(username)])
      .then(([u, page]) => {
        setUser(u);
        // ADR 0004 の `is_followed_by_viewer` で初期 follow 状態を確定
        setFollowing(u.is_followed_by_viewer === true);
        setPosts(page.results);
      })
      .catch((e) => setError((e as Error).message));
  }, [username]);

  async function toggleFollow() {
    if (!user || busy || isMe) return;
    setBusy(true);
    try {
      if (following) {
        await unfollow(username);
        setFollowing(false);
        setUser({ ...user, followers_count: Math.max(0, user.followers_count - 1) });
      } else {
        await follow(username);
        setFollowing(true);
        setUser({ ...user, followers_count: user.followers_count + 1 });
      }
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  if (error) return <p className="text-red-600 text-sm">{error}</p>;
  if (!user || posts === null)
    return <p className="text-sm text-black/50">loading...</p>;

  return (
    <div className="space-y-6">
      <header className="flex items-baseline justify-between">
        <div>
          <h1 className="text-xl font-semibold">@{user.username}</h1>
          {user.bio ? <p className="text-sm mt-1">{user.bio}</p> : null}
          <p className="mt-2 text-xs text-black/60 dark:text-white/60 flex gap-3">
            <span>{user.posts_count} posts</span>
            <span>{user.followers_count} followers</span>
            <span>{user.following_count} following</span>
          </p>
        </div>
        {!isMe ? (
          <button
            type="button"
            onClick={toggleFollow}
            disabled={busy}
            className="text-xs px-3 py-1.5 rounded border disabled:opacity-50"
          >
            {following ? "following" : "follow"}
          </button>
        ) : null}
      </header>
      <section className="space-y-4">
        {posts.length === 0 ? (
          <p className="text-sm text-black/60 dark:text-white/60">投稿はまだありません。</p>
        ) : (
          posts.map((p) => <PostCard key={p.id} post={p} />)
        )}
      </section>
    </div>
  );
}
