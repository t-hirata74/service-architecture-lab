// ADR 0004: answer.body 内の `[#src_<n>]` marker を <CitationLink> でハイライトする.
// 状態: valid な marker は青ハイライト + クリックで source preview / invalid は薄字 (クリック不可).
import React from "react";

const MARKER_REGEX = /\[#src_(\d+)\]/g;

export type CitationStatus = "valid" | "invalid";

export type CitationStatusMap = Map<string, CitationStatus>;
//                                  ^ marker (e.g. "src_3") → status

export type RenderOpts = {
  onCitationClick?: (marker: string, sourceId: number) => void;
};

export function renderBodyWithCitations(
  body: string,
  statuses: CitationStatusMap,
  opts: RenderOpts = {},
): React.ReactNode[] {
  const parts: React.ReactNode[] = [];
  let lastIndex = 0;
  let key = 0;

  for (const match of body.matchAll(MARKER_REGEX)) {
    const marker = match[0].slice(2, -1); // "[#src_3]" → "src_3"
    const sourceId = Number(match[1]);
    const start = match.index ?? 0;

    // marker 直前の plain text
    if (start > lastIndex) {
      parts.push(<span key={`t-${key++}`}>{body.slice(lastIndex, start)}</span>);
    }

    const status = statuses.get(marker) ?? "invalid"; // 不明 marker は invalid 扱い (defensive)
    if (status === "valid") {
      parts.push(
        <button
          key={`c-${key++}`}
          type="button"
          onClick={() => opts.onCitationClick?.(marker, sourceId)}
          className="mx-0.5 inline-flex items-center rounded-md bg-sky-100 px-1.5 py-0.5 text-xs font-medium text-sky-700 hover:bg-sky-200 dark:bg-sky-950 dark:text-sky-300 dark:hover:bg-sky-900"
          title={`source #${sourceId}`}
        >
          {marker}
        </button>,
      );
    } else {
      parts.push(
        <span
          key={`c-${key++}`}
          className="mx-0.5 inline-flex items-center rounded-md bg-zinc-100 px-1.5 py-0.5 text-xs font-medium text-zinc-400 line-through dark:bg-zinc-900 dark:text-zinc-600"
          title="invalid citation (Rails 側で reject された)"
        >
          {marker}
        </span>,
      );
    }

    lastIndex = start + match[0].length;
  }

  if (lastIndex < body.length) {
    parts.push(<span key={`t-${key++}`}>{body.slice(lastIndex)}</span>);
  }

  return parts;
}
