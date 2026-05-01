import Header from "@/components/Header";
import VideoCard from "@/components/VideoCard";
import { searchVideos, type VideoSummary } from "@/lib/videos";

type SearchParams = Promise<{ q?: string }>;

async function loadResults(q: string): Promise<{ items: VideoSummary[]; error: string | null }> {
  if (!q) return { items: [], error: null };
  try {
    return { items: await searchVideos(q), error: null };
  } catch (e) {
    return { items: [], error: e instanceof Error ? e.message : String(e) };
  }
}

export default async function SearchPage({ searchParams }: { searchParams: SearchParams }) {
  const { q = "" } = await searchParams;
  const { items, error } = await loadResults(q.trim());

  return (
    <>
      <Header />
      <main className="mx-auto w-full max-w-6xl flex-1 px-6 py-8">
        <h1 className="mb-2 text-xl font-semibold">
          {q ? `"${q}" の検索結果` : "検索"}
        </h1>
        <p className="mb-6 text-xs opacity-60">
          MySQL FULLTEXT (ngram parser) で日本語タイトル / 説明文を全文検索 (ADR 0004)。
        </p>

        {error && (
          <div className="mb-4 rounded border border-red-500/40 bg-red-500/10 p-3 text-sm">
            {error}
          </div>
        )}

        {!error && q && items.length === 0 && (
          <p className="text-sm opacity-70">「{q}」に一致する動画はありませんでした。</p>
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
