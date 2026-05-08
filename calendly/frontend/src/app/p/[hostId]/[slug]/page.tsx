"use client";

import { FormEvent, use, useEffect, useState } from "react";
import { api } from "../../../../lib/api";
import { Booking, PublicEventType, Slot } from "../../../../lib/types";

export default function PublicBookingPage(props: { params: Promise<{ hostId: string; slug: string }> }) {
  const { hostId, slug } = use(props.params);

  const [meta, setMeta] = useState<PublicEventType | null>(null);
  const [slots, setSlots] = useState<Slot[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [confirmed, setConfirmed] = useState<Booking | null>(null);
  const [picked, setPicked] = useState<Slot | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const inviteeTz = typeof Intl !== "undefined" ? Intl.DateTimeFormat().resolvedOptions().timeZone : "UTC";

  useEffect(() => {
    (async () => {
      try {
        const m = await api<PublicEventType>(`/public/event_types/${hostId}/${slug}`, { skipAuth: true });
        setMeta(m);
        const from = new Date(); from.setUTCMinutes(0, 0, 0);
        const to = new Date(from.getTime() + 7 * 24 * 60 * 60 * 1000);
        const s = await api<Slot[]>(
          `/event_types/${m.id}/slots?from=${from.toISOString()}&to=${to.toISOString()}&tz=${inviteeTz}`,
          { skipAuth: true }
        );
        setSlots(s);
      } catch (e: unknown) {
        setError((e as Error).message);
      }
    })();
  }, [hostId, slug, inviteeTz]);

  async function bookPicked(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (!picked || !meta) return;
    const fd = new FormData(e.currentTarget);
    setSubmitting(true);
    setError(null);
    try {
      const b = await api<Booking>("/bookings", {
        skipAuth: true,
        method: "POST",
        body: JSON.stringify({
          event_type_id: meta.id,
          start_at: picked.start_at_utc,
          invitee_email: fd.get("invitee_email"),
          invitee_name: fd.get("invitee_name"),
          invitee_tz_id: inviteeTz,
        }),
      });
      setConfirmed(b);
    } catch (e: unknown) {
      setError((e as Error).message);
    } finally {
      setSubmitting(false);
    }
  }

  if (error && !meta) return <Layout><p data-testid="error" className="text-rose-600">{error}</p></Layout>;
  if (!meta) return <Layout><p>Loading…</p></Layout>;

  if (confirmed) {
    return (
      <Layout>
        <h1 className="text-2xl font-semibold text-zinc-900">予約確定</h1>
        <p className="mt-2 text-sm text-zinc-600">{meta.host_name} / {meta.title}</p>
        <p className="mt-4 rounded bg-emerald-50 px-4 py-3 text-sm text-emerald-800" data-testid="confirmed-message">
          {new Date(confirmed.start_at).toLocaleString(undefined, { timeZone: inviteeTz })} に予約しました。
        </p>
      </Layout>
    );
  }

  return (
    <Layout>
      <header>
        <h1 className="text-2xl font-semibold text-zinc-900">{meta.host_name}</h1>
        <p className="mt-1 text-sm text-zinc-600">{meta.title} ({meta.duration_minutes} min) · あなたの TZ: {inviteeTz}</p>
      </header>

      {!picked ? (
        <section className="mt-6">
          <h2 className="text-base font-semibold text-zinc-900">空き時間を選んでください</h2>
          <div className="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-3" data-testid="slots">
            {slots.length === 0 && <p className="text-sm text-zinc-500">表示できる空きがありません。</p>}
            {slots.map((s) => (
              <button key={s.start_at_utc} onClick={() => setPicked(s)}
                      data-testid="slot-button"
                      data-slot-utc={s.start_at_utc}
                      className="rounded border border-zinc-200 bg-white px-3 py-2 text-left text-sm hover:border-emerald-400">
                {new Date(s.start_at_utc).toLocaleString(undefined, { timeZone: inviteeTz })}
              </button>
            ))}
          </div>
        </section>
      ) : (
        <form onSubmit={bookPicked} className="mt-6 space-y-4" data-testid="invitee-form">
          <p className="rounded bg-zinc-100 px-3 py-2 text-sm text-zinc-700" data-testid="picked-slot">
            選択中: {new Date(picked.start_at_utc).toLocaleString(undefined, { timeZone: inviteeTz })}
          </p>
          <label className="block">
            <span className="text-sm font-medium text-zinc-700">名前</span>
            <input name="invitee_name" required className="mt-1 block w-full rounded border border-zinc-300 px-3 py-2 text-sm" data-testid="invitee-name" />
          </label>
          <label className="block">
            <span className="text-sm font-medium text-zinc-700">メールアドレス</span>
            <input name="invitee_email" type="email" required className="mt-1 block w-full rounded border border-zinc-300 px-3 py-2 text-sm" data-testid="invitee-email" />
          </label>
          {error && <p data-testid="error" className="text-sm text-rose-600">{error}</p>}
          <div className="flex gap-2">
            <button type="button" onClick={() => setPicked(null)}
                    className="rounded border border-zinc-300 px-4 py-2 text-sm">戻る</button>
            <button type="submit" disabled={submitting} data-testid="confirm-button"
                    className="flex-1 rounded bg-emerald-600 py-2 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-50">
              {submitting ? "予約中…" : "予約を確定"}
            </button>
          </div>
        </form>
      )}
    </Layout>
  );
}

function Layout({ children }: { children: React.ReactNode }) {
  return (
    <main className="min-h-screen bg-zinc-50 px-6 py-12">
      <div className="mx-auto max-w-2xl rounded-md border border-zinc-200 bg-white p-8">{children}</div>
    </main>
  );
}
