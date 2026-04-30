import { notFound } from "next/navigation";
import Link from "next/link";
import Header from "@/components/Header";
import VideoCard from "@/components/VideoCard";
import {
  fetchRecommendations,
  fetchVideo,
  formatDuration,
  formatPublishedAt,
} from "@/lib/videos";

type Params = Promise<{ id: string }>;

export default async function VideoDetailPage({ params }: { params: Params }) {
  const { id } = await params;
  const [video, recs] = await Promise.all([
    fetchVideo(id),
    fetchRecommendations(id),
  ]);
  if (!video) notFound();

  return (
    <>
      <Header />
      <main className="mx-auto grid w-full max-w-6xl flex-1 grid-cols-1 gap-8 px-6 py-8 lg:grid-cols-[minmax(0,1fr)_320px]">
        <article>
          <div className="relative aspect-video overflow-hidden rounded-lg bg-zinc-900">
            {video.thumbnail_url ? (
              /* eslint-disable-next-line @next/next/no-img-element */
              <img
                src={video.thumbnail_url}
                alt={video.title}
                className="h-full w-full object-cover"
              />
            ) : (
              <div className="flex h-full w-full items-center justify-center text-sm uppercase tracking-widest opacity-60">
                video player placeholder
              </div>
            )}
          </div>

          <h1 className="mt-6 text-2xl font-semibold leading-tight">{video.title}</h1>

          <div className="mt-3 flex flex-wrap items-center gap-4 text-sm opacity-80">
            <span>{video.author.name}</span>
            <span className="opacity-60">·</span>
            <span>{formatPublishedAt(video.published_at)}</span>
            <span className="opacity-60">·</span>
            <span>{formatDuration(video.duration_seconds)}</span>
            <span className="opacity-60">·</span>
            <span className="rounded bg-white/10 px-2 py-0.5 text-xs uppercase tracking-wide">
              {video.status}
            </span>
          </div>

          {video.tags.length > 0 && (
            <ul className="mt-3 flex flex-wrap gap-2">
              {video.tags.map((t) => (
                <li key={t} className="rounded bg-white/10 px-2 py-0.5 text-xs">#{t}</li>
              ))}
            </ul>
          )}

          <p className="mt-6 whitespace-pre-line rounded-lg bg-white/5 p-4 text-sm leading-relaxed">
            {video.description ?? "(説明なし)"}
          </p>
        </article>

        <aside>
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wider opacity-70">
            関連動画
          </h2>
          {recs.degraded && (
            <div className="mb-3 rounded border border-yellow-500/40 bg-yellow-500/10 p-3 text-xs">
              ai-worker と通信できなかったため関連動画は表示されません
            </div>
          )}
          {!recs.degraded && recs.items.length === 0 && (
            <p className="text-xs opacity-60">類似する動画がまだありません。</p>
          )}
          <ul className="flex flex-col gap-3">
            {recs.items.map((rec) => (
              <li key={rec.id} className="flex flex-col gap-1">
                <VideoCard video={rec} />
                <span className="text-[10px] opacity-50">
                  similarity score: {rec.score.toFixed(2)}
                </span>
              </li>
            ))}
          </ul>
          <Link
            href="/"
            className="mt-6 inline-block text-xs underline opacity-60 hover:opacity-90"
          >
            ← 一覧に戻る
          </Link>
        </aside>
      </main>
    </>
  );
}
