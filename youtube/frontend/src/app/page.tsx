import Header from "@/components/Header";
import VideoCard from "@/components/VideoCard";
import { fetchVideos, type VideoSummary } from "@/lib/videos";

async function loadVideos(): Promise<{ items: VideoSummary[]; error: string | null }> {
  try {
    const items = await fetchVideos();
    return { items, error: null };
  } catch (e) {
    return { items: [], error: e instanceof Error ? e.message : String(e) };
  }
}

export default async function Home() {
  const { items, error } = await loadVideos();

  return (
    <>
      <Header />
      <main className="mx-auto w-full max-w-6xl flex-1 px-6 py-8">
        <h1 className="mb-6 text-2xl font-semibold">Trending</h1>
        {error && (
          <div className="rounded border border-red-500/40 bg-red-500/10 p-4 text-sm">
            backend に接続できませんでした: {error}
            <p className="mt-1 opacity-70">
              `cd youtube/backend && bundle exec rails server -p 3020` を起動してください。
            </p>
          </div>
        )}
        {!error && items.length === 0 && (
          <p className="text-sm opacity-70">公開済み動画がありません。`bundle exec rails db:seed` を実行してください。</p>
        )}
        <ul className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {items.map((v) => (
            <li key={v.id}>
              <VideoCard video={v} />
            </li>
          ))}
        </ul>
      </main>
    </>
  );
}
