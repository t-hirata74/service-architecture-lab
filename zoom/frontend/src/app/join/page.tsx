"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function JoinPage() {
  const router = useRouter();
  const [meetingId, setMeetingId] = useState("");

  return (
    <div className="max-w-md mx-auto bg-white border border-zinc-200 rounded-md p-6">
      <h1 className="text-xl font-semibold text-zinc-900">参加コードで join</h1>
      <p className="text-xs text-zinc-500 mt-1">会議 id を入力すると詳細ページに遷移する。</p>
      <form
        className="mt-4 flex gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          if (meetingId) router.push(`/meetings/${meetingId}`);
        }}
      >
        <input
          value={meetingId}
          onChange={(e) => setMeetingId(e.target.value)}
          required
          inputMode="numeric"
          placeholder="123"
          className="flex-1 px-3 py-2 rounded-md border border-zinc-300 bg-white"
        />
        <button
          type="submit"
          className="px-4 py-2 rounded-md bg-[var(--color-accent)] text-white text-sm font-medium hover:opacity-90"
        >
          Open
        </button>
      </form>
    </div>
  );
}
