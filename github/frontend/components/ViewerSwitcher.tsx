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
    <div className="flex items-center gap-3 text-sm">
      <span className="text-zinc-500">viewer:</span>
      <span className="font-mono">
        {viewer?.login ?? <em className="text-zinc-400">unauthenticated</em>}
      </span>
      <input
        className="border rounded px-2 py-1 text-xs font-mono"
        placeholder="login"
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
      />
      <button
        className="px-2 py-1 text-xs border rounded hover:bg-zinc-100"
        onClick={() => setViewerLogin(draft.trim() || null)}
      >
        switch
      </button>
      {viewer && (
        <button
          className="px-2 py-1 text-xs border rounded hover:bg-zinc-100"
          onClick={() => setViewerLogin(null)}
        >
          logout
        </button>
      )}
    </div>
  );
}
