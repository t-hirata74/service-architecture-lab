"use client";

import { use, useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import type { Meeting, Summary } from "@/lib/types";

const STATUS_BADGE: Record<Meeting["status"], string> = {
  scheduled: "bg-zinc-100 text-zinc-700",
  waiting_room: "bg-amber-100 text-amber-800",
  live: "bg-green-100 text-green-800",
  ended: "bg-zinc-200 text-zinc-700",
  recorded: "bg-blue-100 text-blue-800",
  summarized: "bg-violet-100 text-violet-800",
  recording_failed: "bg-red-100 text-red-800",
  summarize_failed: "bg-red-100 text-red-800",
};

export default function MeetingDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const [meeting, setMeeting] = useState<Meeting | null>(null);
  const [summary, setSummary] = useState<Summary | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [me, setMe] = useState<number | null>(null);

  const refresh = useCallback(async () => {
    try {
      const m = await api<Meeting>(`/meetings/${id}`);
      setMeeting(m);
      if (m.status === "summarized") {
        try {
          const s = await api<Summary>(`/meetings/${id}/summary`);
          setSummary(s);
        } catch {
          /* not ready */
        }
      }
    } catch (err) {
      setError((err as Error).message);
    }
  }, [id]);

  useEffect(() => {
    // current user の id は JWT payload から取り出す (簡易)。
    const t = (typeof window !== "undefined" && localStorage.getItem("zoom-jwt")) || null;
    if (t) {
      try {
        const payload = JSON.parse(atob(t.split(".")[1]));
        setMe(typeof payload.account_id === "number" ? payload.account_id : null);
      } catch {
        /* malformed */
      }
    }
    refresh();
    const iv = setInterval(refresh, 2000);
    return () => clearInterval(iv);
  }, [refresh]);

  if (error) return <div className="text-[var(--color-danger)] text-sm">{error}</div>;
  if (!meeting) return <div className="text-zinc-500 text-sm">Loading…</div>;

  const isHost = me === meeting.host_id;
  const isCoHost = !!meeting.co_hosts?.includes(me ?? -1);

  async function action(path: string, body?: unknown) {
    setError(null);
    try {
      await api(`/meetings/${id}${path}`, { method: "POST", body: body ? JSON.stringify(body) : undefined });
      await refresh();
    } catch (err) {
      const e = err as { status?: number; body?: unknown; message?: string };
      setError(JSON.stringify(e.body ?? e.message));
    }
  }

  return (
    <div className="space-y-4">
      <header className="bg-white border border-zinc-200 rounded-md p-5">
        <div className="flex items-center justify-between gap-3 flex-wrap">
          <div>
            <h1 className="text-2xl font-semibold text-zinc-900">{meeting.title}</h1>
            <div className="text-xs text-zinc-500 mt-1">id={meeting.id} / host_id={meeting.host_id}</div>
          </div>
          <span className={`px-3 py-1 text-xs rounded-full font-medium ${STATUS_BADGE[meeting.status]}`}>
            {meeting.status}
          </span>
        </div>
      </header>

      <section className="bg-white border border-zinc-200 rounded-md p-5">
        <h2 className="text-sm font-semibold text-zinc-900">Lifecycle (ADR 0001)</h2>
        <div className="flex flex-wrap gap-2 mt-3">
          {isHost && meeting.status === "scheduled" && (
            <Btn testid="btn-open" onClick={() => action("/open")}>Open waiting room</Btn>
          )}
          {isHost && meeting.status === "waiting_room" && (
            <Btn testid="btn-start" onClick={() => action("/start")}>Go live</Btn>
          )}
          {isHost && meeting.status === "live" && (
            <Btn testid="btn-end" variant="danger" onClick={() => action("/end")}>End meeting</Btn>
          )}
          {isHost && meeting.status === "summarize_failed" && (
            <Btn testid="btn-retry-summary" onClick={() => action("/retry_summary")}>Retry summary</Btn>
          )}
          {!isHost && !isCoHost && ["scheduled", "waiting_room", "live"].includes(meeting.status) && (
            <Btn testid="btn-join" onClick={() => action("/join")}>Join (waiting)</Btn>
          )}
        </div>
      </section>

      <section className="bg-white border border-zinc-200 rounded-md p-5">
        <h2 className="text-sm font-semibold text-zinc-900">Participants</h2>
        <ul className="mt-3 divide-y divide-zinc-100">
          {meeting.participants?.length === 0 && (
            <li className="text-xs text-zinc-500 py-2">参加者なし</li>
          )}
          {meeting.participants?.map((p) => (
            <li key={p.id} className="py-2 flex items-center justify-between">
              <div>
                <div className="text-sm text-zinc-900">{p.display_name}</div>
                <div className="text-xs text-zinc-500">user_id={p.user_id} / status={p.status}</div>
              </div>
              <div className="flex gap-2">
                {(isHost || isCoHost) && p.status === "waiting" && (
                  <Btn
                    testid={`btn-admit-${p.user_id}`}
                    size="sm"
                    onClick={() => action("/admit", { user_id: p.user_id })}
                  >
                    Admit
                  </Btn>
                )}
                {isHost && meeting.status === "live" && p.status === "live" && p.user_id !== meeting.host_id && (
                  <Btn
                    testid={`btn-transfer-${p.user_id}`}
                    size="sm"
                    variant="ghost"
                    onClick={() => action("/transfer_host", { to_user_id: p.user_id, reason: "voluntary" })}
                  >
                    Transfer host
                  </Btn>
                )}
              </div>
            </li>
          ))}
        </ul>
      </section>

      {summary && (
        <section className="bg-white border border-zinc-200 rounded-md p-5">
          <h2 className="text-sm font-semibold text-zinc-900">Summary (ADR 0003)</h2>
          <pre className="mt-3 whitespace-pre-wrap text-xs text-zinc-700 font-mono">{summary.body}</pre>
          <div className="text-xs text-zinc-400 mt-2">generated_at: {summary.generated_at}</div>
        </section>
      )}
    </div>
  );
}

type BtnProps = {
  children: React.ReactNode;
  onClick: () => void;
  variant?: "primary" | "danger" | "ghost";
  size?: "md" | "sm";
  testid?: string;
};

function Btn({ children, onClick, variant = "primary", size = "md", testid }: BtnProps) {
  const base =
    "inline-flex items-center font-medium rounded-md border transition-colors disabled:opacity-50";
  const sizing = size === "sm" ? "px-2.5 py-1 text-xs" : "px-4 py-2 text-sm";
  const styles =
    variant === "danger"
      ? "bg-[var(--color-danger)] text-white border-transparent hover:opacity-90"
      : variant === "ghost"
      ? "bg-white border-zinc-300 text-zinc-700 hover:bg-zinc-50"
      : "bg-[var(--color-accent)] text-white border-transparent hover:opacity-90";
  return (
    <button type="button" data-testid={testid} onClick={onClick} className={`${base} ${sizing} ${styles}`}>
      {children}
    </button>
  );
}
