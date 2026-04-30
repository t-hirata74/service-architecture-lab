"use client";

import { useEffect, useState } from "react";
import { useRouter, useParams } from "next/navigation";
import Header from "@/components/Header";
import { fetchVideoStatus, publishVideo, type VideoStatus } from "@/lib/videos";

export default function ProcessingPage() {
  const router = useRouter();
  const params = useParams<{ id: string }>();
  const id = params.id;

  const [status, setStatus] = useState<VideoStatus | null>(null);
  const [polls, setPolls] = useState(0);
  const [publishing, setPublishing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!id) return;
    if (status === "ready" || status === "published" || status === "failed") return;

    const timer = setTimeout(async () => {
      try {
        const next = await fetchVideoStatus(id);
        setStatus(next);
        setPolls((n) => n + 1);
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e));
      }
    }, status == null ? 0 : 1000);

    return () => clearTimeout(timer);
  }, [id, status, polls]);

  async function onPublish() {
    setError(null);
    setPublishing(true);
    try {
      await publishVideo(id);
      router.push(`/videos/${id}`);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setPublishing(false);
    }
  }

  return (
    <>
      <Header />
      <main className="mx-auto w-full max-w-xl flex-1 px-6 py-12">
        <h1 className="mb-2 text-2xl font-semibold">アップロード処理中</h1>
        <p className="mb-6 text-sm opacity-70">
          状態機械: uploaded → transcoding → ready → published。
          Solid Queue がエンキューしたモック変換ジョブを待っています。
        </p>

        <div className="rounded-lg border border-white/10 bg-white/5 p-6">
          <Stepper status={status} />
          <div className="mt-6 text-sm">
            <div>video_id: <span className="font-mono">{id}</span></div>
            <div>status: <span className="font-mono">{status ?? "loading…"}</span></div>
            <div className="opacity-60">poll: {polls}</div>
          </div>
        </div>

        {status === "ready" && (
          <button
            onClick={onPublish}
            disabled={publishing}
            className="mt-6 w-full rounded bg-accent px-4 py-2 text-sm font-medium disabled:opacity-50"
          >
            {publishing ? "公開中…" : "公開する"}
          </button>
        )}

        {status === "published" && (
          <div className="mt-6 rounded border border-emerald-500/40 bg-emerald-500/10 p-3 text-sm">
            公開済み: <a href={`/videos/${id}`} className="underline">詳細を見る</a>
          </div>
        )}

        {status === "failed" && (
          <div className="mt-6 rounded border border-red-500/40 bg-red-500/10 p-3 text-sm">
            変換に失敗しました（添付が見つからない等）。
          </div>
        )}

        {error && (
          <div className="mt-4 rounded border border-yellow-500/40 bg-yellow-500/10 p-3 text-xs">
            {error}
          </div>
        )}
      </main>
    </>
  );
}

function Stepper({ status }: { status: VideoStatus | null }) {
  const steps: VideoStatus[] = ["uploaded", "transcoding", "ready", "published"];
  const currentIndex = status ? steps.indexOf(status === "failed" ? "transcoding" : status) : -1;
  return (
    <ol className="flex items-center justify-between text-xs">
      {steps.map((s, i) => {
        const reached = i <= currentIndex;
        const failed = status === "failed" && s === "transcoding";
        return (
          <li key={s} className="flex flex-col items-center gap-1">
            <span
              className={
                "flex h-8 w-8 items-center justify-center rounded-full border " +
                (failed
                  ? "border-red-500/60 bg-red-500/20 text-red-200"
                  : reached
                  ? "border-accent bg-accent/20"
                  : "border-white/20 opacity-50")
              }
            >
              {i + 1}
            </span>
            <span className={reached ? "" : "opacity-50"}>{s}</span>
          </li>
        );
      })}
    </ol>
  );
}
