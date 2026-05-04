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
    ctrlRef.current?.abort();

    setState({ kind: "submitting" });
    setBody("");
    setStatuses(new Map());
    setCitations([]);

    try {
      const created = await createQuery(text);
      setState({ kind: "streaming", queryId: created.query_id });

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
      <header className="mb-8 flex items-center gap-3">
        <span
          aria-hidden
          className="size-10 rounded-xl bg-gradient-to-br from-[var(--accent)] to-[var(--accent-hover)] grid place-items-center text-[var(--accent-fg)] text-xl font-bold shadow-[var(--shadow)]"
        >
          ⌕
        </span>
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Perplexity-lab Console</h1>
          <p className="text-sm text-[var(--fg-muted)]">
            ADR 0003 SSE / ADR 0004 引用整合性 · ローカルコーパス 5 件に対して RAG パイプラインを実行.
          </p>
        </div>
      </header>

      <form
        className="mb-8"
        onSubmit={(e) => {
          e.preventDefault();
          submit();
        }}
      >
        <textarea
          className="w-full rounded-[var(--radius-lg)] border border-[var(--border-strong)] bg-[var(--bg-elevated)] px-4 py-3 text-base shadow-[var(--shadow-sm)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)] focus-visible:border-[var(--accent)] transition-colors resize-y"
          rows={2}
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder="質問を入力..."
        />
        <div className="mt-3 flex items-center justify-between">
          <button
            type="submit"
            disabled={isSubmitDisabled}
            className="inline-flex items-center gap-1.5 rounded-md bg-[var(--accent)] px-5 h-10 text-sm font-semibold text-[var(--accent-fg)] shadow-[var(--shadow-sm)] hover:bg-[var(--accent-hover)] transition-colors disabled:cursor-not-allowed disabled:opacity-50"
          >
            {state.kind === "submitting" || state.kind === "streaming" ? (
              <span className="size-3 rounded-full bg-[var(--accent-fg)] animate-pulse" />
            ) : (
              <span aria-hidden>↗</span>
            )}
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
        <div className="mt-6 rounded-md border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700">
          <strong className="font-semibold">エラー:</strong> {state.reason}
          {state.detail && <div className="mt-1 text-xs opacity-75 font-mono">{state.detail}</div>}
        </div>
      )}
    </div>
  );
}

function StatusBadge({ state }: { state: StreamState }) {
  const map: Record<StreamState["kind"], { text: string; cls: string; dot: string }> = {
    idle: { text: "待機中", cls: "bg-[var(--bg-subtle)] text-[var(--fg-muted)] border-[var(--border)]", dot: "bg-[var(--fg-subtle)]" },
    submitting: {
      text: "POST /queries…",
      cls: "bg-amber-50 text-amber-700 border-amber-200",
      dot: "bg-amber-500 animate-pulse",
    },
    streaming: {
      text: "SSE 受信中…",
      cls: "bg-[color-mix(in_oklab,var(--accent)_15%,white)] text-[var(--accent-hover)] border-[color-mix(in_oklab,var(--accent)_30%,white)]",
      dot: "bg-[var(--accent)] animate-pulse",
    },
    completed: {
      text: "完了",
      cls: "bg-emerald-50 text-emerald-700 border-emerald-200",
      dot: "bg-emerald-500",
    },
    error: { text: "エラー", cls: "bg-rose-50 text-rose-700 border-rose-200", dot: "bg-rose-500" },
  };
  const { text, cls, dot } = map[state.kind];
  return (
    <span className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-xs font-medium ${cls}`}>
      <span className={`size-1.5 rounded-full ${dot}`} />
      {text}
    </span>
  );
}

function Answer({ body, statuses }: { body: string; statuses: CitationStatusMap }) {
  if (body.length === 0) {
    return (
      <div className="rounded-[var(--radius-lg)] border border-dashed border-[var(--border)] bg-[var(--bg-subtle)]/40 px-4 py-12 text-center text-sm text-[var(--fg-subtle)]">
        <div className="text-3xl mb-2 opacity-40">💭</div>
        クエリを実行すると、ここに回答が逐次表示されます。
      </div>
    );
  }
  return (
    <article className="rounded-[var(--radius-lg)] border border-[var(--border)] bg-[var(--bg-elevated)] px-6 py-5 leading-7 shadow-[var(--shadow-sm)]">
      {renderBodyWithCitations(body, statuses)}
    </article>
  );
}

function CitationList({ citations }: { citations: CitationListEntry[] }) {
  if (citations.length === 0) return null;
  const validCount = citations.filter((c) => c.valid).length;
  const invalidCount = citations.length - validCount;
  return (
    <section className="mt-6">
      <h2 className="mb-3 text-xs font-semibold uppercase tracking-wide text-[var(--fg-muted)]">
        引用 <span className="text-emerald-600">{validCount} 件 valid</span>
        {" / "}
        <span className="text-rose-600">{invalidCount} 件 invalid</span>
      </h2>
      <ul className="space-y-1.5 text-sm bg-[var(--bg-elevated)] border border-[var(--border)] rounded-[var(--radius)] p-3 shadow-[var(--shadow-sm)]">
        {citations.map((c, i) => (
          <li
            key={i}
            className={`flex items-center gap-2 ${
              c.valid ? "" : "text-[var(--fg-subtle)] line-through"
            }`}
          >
            <span className="font-mono text-xs text-[var(--fg-muted)] min-w-[3ch]">[{c.marker}]</span>
            <span>source #{c.sourceId}</span>
            {!c.valid && (
              <span className="ml-2 rounded bg-rose-50 border border-rose-200 px-1.5 text-xs text-rose-700">
                ADR 0004 reject
              </span>
            )}
          </li>
        ))}
      </ul>
    </section>
  );
}
