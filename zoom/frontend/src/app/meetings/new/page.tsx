"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/lib/api";
import type { Meeting } from "@/lib/types";

export default function NewMeetingPage() {
  const router = useRouter();
  const [title, setTitle] = useState("Weekly sync");
  const [scheduledAt, setScheduledAt] = useState(() => {
    const d = new Date();
    d.setMinutes(d.getMinutes() + 15);
    return d.toISOString().slice(0, 16); // datetime-local
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      const meeting = await api<Meeting>("/meetings", {
        method: "POST",
        body: JSON.stringify({ title, scheduled_start_at: new Date(scheduledAt).toISOString() }),
      });
      router.push(`/meetings/${meeting.id}`);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="max-w-md mx-auto bg-white border border-zinc-200 rounded-md p-6">
      <h1 className="text-xl font-semibold text-zinc-900">会議を作成</h1>
      <p className="text-xs text-zinc-500 mt-1">作成された会議は scheduled 状態。ホストが open すると waiting_room に進む (ADR 0001)。</p>

      <form className="mt-4 space-y-3" onSubmit={onSubmit}>
        <div>
          <label htmlFor="title" className="block text-xs text-zinc-500 mb-1">Title</label>
          <input
            id="title"
            data-testid="title-input"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            required
            className="w-full px-3 py-2 rounded-md border border-zinc-300 bg-white"
          />
        </div>
        <div>
          <label htmlFor="scheduled_at" className="block text-xs text-zinc-500 mb-1">Scheduled start</label>
          <input
            id="scheduled_at"
            data-testid="scheduled-at-input"
            type="datetime-local"
            value={scheduledAt}
            onChange={(e) => setScheduledAt(e.target.value)}
            required
            className="w-full px-3 py-2 rounded-md border border-zinc-300 bg-white"
          />
        </div>
        {error && <div className="text-sm text-[var(--color-danger)]">{error}</div>}
        <button
          type="submit"
          data-testid="submit-button"
          disabled={busy}
          className="w-full px-4 py-2 rounded-md bg-[var(--color-accent)] text-white text-sm font-medium hover:opacity-90 disabled:opacity-50"
        >
          {busy ? "Creating…" : "Create meeting"}
        </button>
      </form>
    </div>
  );
}
