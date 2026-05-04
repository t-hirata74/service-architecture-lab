import Link from "next/link";
import { VideoSummary, formatDuration, formatPublishedAt } from "@/lib/videos";

export default function VideoCard({ video }: { video: VideoSummary }) {
  return (
    <Link
      href={`/videos/${video.id}`}
      className="group flex flex-col gap-3 rounded-[var(--radius-lg)] p-2 transition-all hover:bg-[var(--bg-subtle)]"
    >
      <div className="relative aspect-video overflow-hidden rounded-[var(--radius)] bg-[var(--bg-subtle)] shadow-[var(--shadow-sm)] group-hover:shadow-[var(--shadow)] transition-shadow">
        {video.thumbnail_url ? (
          /* eslint-disable-next-line @next/next/no-img-element */
          <img
            src={video.thumbnail_url}
            alt={video.title}
            className="h-full w-full object-cover transition-transform duration-300 group-hover:scale-105"
          />
        ) : (
          <div className="absolute inset-0 flex flex-col items-center justify-center gap-1 text-[var(--fg-subtle)]">
            <span className="text-2xl opacity-50">▶</span>
            <span className="text-[10px] uppercase tracking-widest opacity-60">
              thumbnail
            </span>
          </div>
        )}
        <span className="absolute bottom-2 right-2 rounded bg-black/80 text-white px-1.5 py-0.5 text-xs font-medium tabular-nums backdrop-blur-sm">
          {formatDuration(video.duration_seconds)}
        </span>
      </div>
      <div className="px-1">
        <h3 className="line-clamp-2 text-sm font-semibold leading-snug text-[var(--fg)] group-hover:text-[var(--accent)] transition-colors">
          {video.title}
        </h3>
        <p className="mt-1 text-xs text-[var(--fg-muted)]">{video.author.name}</p>
        <p className="text-xs text-[var(--fg-subtle)]">{formatPublishedAt(video.published_at)}</p>
        {video.tags.length > 0 && (
          <ul className="mt-2 flex flex-wrap gap-1">
            {video.tags.slice(0, 3).map((t) => (
              <li
                key={t}
                className="rounded-full bg-[var(--bg-subtle)] border border-[var(--border)] px-2 py-0.5 text-[10px] text-[var(--fg-muted)]"
              >
                #{t}
              </li>
            ))}
          </ul>
        )}
      </div>
    </Link>
  );
}
