import { notFound } from "next/navigation";
import Header from "@/components/Header";
import { fetchVideo, formatDuration, formatPublishedAt } from "@/lib/videos";

type Params = Promise<{ id: string }>;

export default async function VideoDetailPage({ params }: { params: Params }) {
  const { id } = await params;
  const video = await fetchVideo(id);
  if (!video) notFound();

  return (
    <>
      <Header />
      <main className="mx-auto w-full max-w-5xl flex-1 px-6 py-8">
        <div className="aspect-video overflow-hidden rounded-lg bg-zinc-900">
          <div className="flex h-full w-full items-center justify-center text-sm uppercase tracking-widest opacity-60">
            video player placeholder
          </div>
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

        <p className="mt-6 text-xs opacity-50">
          コメント・関連動画は Phase 4-5 で実装予定。
        </p>
      </main>
    </>
  );
}
