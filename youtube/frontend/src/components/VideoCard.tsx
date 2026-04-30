import Link from "next/link";
import { VideoSummary, formatDuration, formatPublishedAt } from "@/lib/videos";

export default function VideoCard({ video }: { video: VideoSummary }) {
  return (
    <Link
      href={`/videos/${video.id}`}
      className="group flex flex-col gap-2 rounded-lg p-2 transition hover:bg-white/5"
    >
      <div className="relative aspect-video overflow-hidden rounded-md bg-zinc-800">
        <div className="absolute inset-0 flex items-center justify-center text-xs uppercase tracking-widest opacity-60 group-hover:opacity-90">
          thumbnail placeholder
        </div>
        <span className="absolute bottom-2 right-2 rounded bg-black/80 px-1.5 py-0.5 text-xs">
          {formatDuration(video.duration_seconds)}
        </span>
      </div>
      <div>
        <h3 className="line-clamp-2 text-sm font-medium leading-snug">{video.title}</h3>
        <p className="mt-1 text-xs opacity-70">{video.author.name}</p>
        <p className="text-xs opacity-50">{formatPublishedAt(video.published_at)}</p>
        {video.tags.length > 0 && (
          <ul className="mt-2 flex flex-wrap gap-1">
            {video.tags.slice(0, 3).map((t) => (
              <li key={t} className="rounded bg-white/10 px-1.5 py-0.5 text-[10px] opacity-80">
                #{t}
              </li>
            ))}
          </ul>
        )}
      </div>
    </Link>
  );
}
