"use client";

import React, { useCallback, useRef, useState } from "react";
import { createQuery, API_BASE } from "@/lib/api";
import { openSseStream } from "@/lib/sse";
import {
  CitationStatusMap,
  renderBodyWithCitations,
} from "@/lib/render-citations";

type StreamState =
  | { kind: "idle" }
  | { kind: "submitting" }
  | { kind: "streaming"; queryId: number }
  | { kind: "completed"; queryId: number }
  | { kind: "error"; reason: string; detail?: string };

type CitationListEntry = {
  marker: string;
  sourceId: number;
  chunkId: number | null;
  position: number;
  valid: boolean;
};

export function QueryConsole() {
  const [text, setText] = useState("東京タワーはいつ完成した？");
  const [body, setBody] = useState("");
  const [statuses, setStatuses] = useState<CitationStatusMap>(new Map());
  const [citations, setCitations] = useState<CitationListEntry[]>([]);
  const [state, setState] = useState<StreamState>({ kind: "idle" });
  const ctrlRef = useRef<AbortController | null>(null);

  const submit = useCallback(async () => {
    // 走行中の stream があれば abort
    ctrlRef.current?.abort();

    setState({ kind: "submitting" });
    setBody("");
    setStatuses(new Map());
    setCitations([]);

    try {
      const created = await createQuery(text);
      setState({ kind: "streaming", queryId: created.query_id });

      // SSE 開始. stream_url は backend から相対/絶対両方許容
      const url = created.stream_url.startsWith("http")
        ? created.stream_url
        : `${API_BASE}${created.stream_url}`;

      ctrlRef.current = openSseStream(url, {
        onEvent: (ev) => {
          if (ev.event === "chunk") {
            const data = ev.data as { text: string; ord: number };
            setBody((prev) => prev + data.text);
          } else if (ev.event === "citation") {
            const data = ev.data as {
              marker: string;
              source_id: number;
              chunk_id: number | null;
              position: number;
            };
            setStatuses((prev) => {
              const next = new Map(prev);
              next.set(data.marker, "valid");
              return next;
            });
            setCitations((prev) => [
              ...prev,
              {
                marker: data.marker,
                sourceId: data.source_id,
                chunkId: data.chunk_id,
                position: data.position,
                valid: true,
              },
            ]);
          } else if (ev.event === "citation_invalid") {
            const data = ev.data as { marker: string; source_id: number; position: number };
            setStatuses((prev) => {
              const next = new Map(prev);
              next.set(data.marker, "invalid");
              return next;
            });
            setCitations((prev) => [
              ...prev,
              {
                marker: data.marker,
                sourceId: data.source_id,
                chunkId: null,
                position: data.position,
                valid: false,
              },
            ]);
          } else if (ev.event === "done") {
            setState((prev) =>
              prev.kind === "streaming" ? { kind: "completed", queryId: prev.queryId } : prev,
            );
          } else if (ev.event === "error") {
            const data = ev.data as { reason: string; detail?: string };
            setState({ kind: "error", reason: data.reason, detail: data.detail });
          }
        },
        onError: (err) => {
          setState({
            kind: "error",
            reason: "network",
            detail: err instanceof Error ? err.message : String(err),
          });
        },
      });
    } catch (e) {
      setState({
        kind: "error",
        reason: "submit_failed",
        detail: e instanceof Error ? e.message : String(e),
      });
    }
  }, [text]);

  const isSubmitDisabled = state.kind === "submitting" || state.kind === "streaming";

  return (
    <div className="mx-auto max-w-3xl py-12 px-6">
      <h1 className="mb-6 text-3xl font-bold tracking-tight">Perplexity-lab Console</h1>
      <p className="mb-8 text-sm text-zinc-500 dark:text-zinc-400">
        ADR 0003 SSE / ADR 0004 引用整合性. ローカルコーパス 5 件に対して RAG パイプラインを実行.
      </p>

      <form
        className="mb-8"
        onSubmit={(e) => {
          e.preventDefault();
          submit();
        }}
      >
        <textarea
          className="w-full rounded-lg border border-zinc-300 bg-white px-4 py-3 text-base shadow-sm focus:border-sky-400 focus:outline-none focus:ring-2 focus:ring-sky-200 dark:border-zinc-700 dark:bg-zinc-900"
          rows={2}
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder="質問を入力..."
        />
        <div className="mt-3 flex items-center justify-between">
          <button
            type="submit"
            disabled={isSubmitDisabled}
            className="inline-flex items-center rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-sky-500 disabled:cursor-not-allowed disabled:bg-zinc-400"
          >
            {state.kind === "submitting"
              ? "送信中…"
              : state.kind === "streaming"
                ? "ストリーミング中…"
                : "クエリを実行"}
          </button>
          <StatusBadge state={state} />
        </div>
      </form>

      <Answer body={body} statuses={statuses} />

      <CitationList citations={citations} />

      {state.kind === "error" && (
        <div className="mt-6 rounded-md bg-red-50 px-4 py-3 text-sm text-red-700 dark:bg-red-950 dark:text-red-300">
          <strong>エラー:</strong> {state.reason}
          {state.detail && <div className="mt-1 text-xs opacity-75">{state.detail}</div>}
        </div>
      )}
    </div>
  );
}

function StatusBadge({ state }: { state: StreamState }) {
  const map: Record<StreamState["kind"], { text: string; cls: string }> = {
    idle: { text: "待機中", cls: "bg-zinc-100 text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400" },
    submitting: {
      text: "POST /queries…",
      cls: "bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-300",
    },
    streaming: {
      text: "SSE 受信中…",
      cls: "bg-sky-100 text-sky-700 dark:bg-sky-950 dark:text-sky-300",
    },
    completed: {
      text: "完了",
      cls: "bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-300",
    },
    error: { text: "エラー", cls: "bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-300" },
  };
  const { text, cls } = map[state.kind];
  return (
    <span className={`rounded-full px-3 py-1 text-xs font-medium ${cls}`}>{text}</span>
  );
}

function Answer({ body, statuses }: { body: string; statuses: CitationStatusMap }) {
  if (body.length === 0) {
    return (
      <div className="rounded-lg border border-dashed border-zinc-300 px-4 py-12 text-center text-sm text-zinc-400 dark:border-zinc-700">
        クエリを実行すると、ここに回答が逐次表示されます。
      </div>
    );
  }
  return (
    <article className="rounded-lg border border-zinc-200 bg-white px-5 py-4 leading-7 dark:border-zinc-800 dark:bg-zinc-900">
      {renderBodyWithCitations(body, statuses)}
    </article>
  );
}

function CitationList({ citations }: { citations: CitationListEntry[] }) {
  if (citations.length === 0) return null;
  return (
    <section className="mt-6">
      <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-zinc-500">
        引用 ({citations.filter((c) => c.valid).length} 件 valid /{" "}
        {citations.filter((c) => !c.valid).length} 件 invalid)
      </h2>
      <ul className="space-y-1 text-sm">
        {citations.map((c, i) => (
          <li
            key={i}
            className={`flex items-center gap-2 ${
              c.valid ? "" : "text-zinc-400 line-through dark:text-zinc-600"
            }`}
          >
            <span className="font-mono text-xs text-zinc-500">[{c.marker}]</span>
            <span>source #{c.sourceId}</span>
            {!c.valid && (
              <span className="ml-2 rounded bg-red-100 px-1.5 text-xs text-red-700 dark:bg-red-950 dark:text-red-300">
                ADR 0004 reject
              </span>
            )}
          </li>
        ))}
      </ul>
    </section>
  );
}
