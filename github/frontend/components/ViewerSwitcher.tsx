"use client";

import { useState } from "react";
import { useQuery, gql } from "urql";
import { setViewerLogin } from "@/lib/viewer";

const VIEWER_QUERY = gql`
  query Viewer { viewer { login name email } }
`;

export default function ViewerSwitcher() {
  const [draft, setDraft] = useState("");
  const [{ data }] = useQuery({ query: VIEWER_QUERY });
  const viewer = data?.viewer;

  return (
    <div className="flex items-center gap-2 text-sm">
      <span className="text-[var(--fg-muted)] hidden sm:inline">viewer:</span>
      <span className="font-mono px-2 py-0.5 rounded bg-[var(--bg-subtle)] border border-[var(--border)] text-xs">
        {viewer?.login ?? <em className="text-[var(--fg-subtle)]">anonymous</em>}
      </span>
      <input
        className="h-8 px-2 border border-[var(--border-strong)] rounded-md text-xs font-mono w-28 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)] focus-visible:border-[var(--accent)] transition-colors"
        placeholder="login"
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
      />
      <button
        className="h-8 px-3 text-xs border border-[var(--border-strong)] rounded-md hover:bg-[var(--bg-subtle)] hover:border-[var(--accent)] transition-colors font-medium"
        onClick={() => setViewerLogin(draft.trim() || null)}
      >
        switch
      </button>
      {viewer && (
        <button
          className="h-8 px-3 text-xs border border-[var(--border-strong)] rounded-md hover:bg-[var(--bg-subtle)] transition-colors text-[var(--fg-muted)]"
          onClick={() => setViewerLogin(null)}
        >
          logout
        </button>
      )}
    </div>
  );
}
