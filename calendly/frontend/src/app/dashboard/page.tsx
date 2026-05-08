"use client";

import { FormEvent, useEffect, useState } from "react";
import { api, logout } from "../../lib/api";
import { AvailabilityRule, Booking, EventType } from "../../lib/types";

export default function Dashboard() {
  const [eventTypes, setEventTypes] = useState<EventType[] | null>(null);
  const [rules, setRules] = useState<AvailabilityRule[] | null>(null);
  const [bookings, setBookings] = useState<Booking[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => { reload(); }, []);

  async function reload() {
    try {
      const [ets, rs, bs] = await Promise.all([
        api<EventType[]>("/event_types"),
        api<AvailabilityRule[]>("/availability_rules"),
        api<Booking[]>("/bookings"),
      ]);
      setEventTypes(ets); setRules(rs); setBookings(bs);
    } catch (e: unknown) {
      setError((e as Error).message);
    }
  }

  async function createEventType(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    try {
      await api("/event_types", {
        method: "POST",
        body: JSON.stringify({
          slug: fd.get("slug"),
          title: fd.get("title"),
          duration_minutes: Number(fd.get("duration_minutes") || 30),
          min_notice_minutes: 0,
          max_advance_days: 60,
          active: true,
        }),
      });
      (e.currentTarget as HTMLFormElement).reset();
      reload();
    } catch (err: unknown) {
      setError((err as Error).message);
    }
  }

  async function createRule(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    try {
      await api("/availability_rules", {
        method: "POST",
        body: JSON.stringify({
          rrule: fd.get("rrule"),
          start_time_of_day: fd.get("start_time_of_day"),
          end_time_of_day:   fd.get("end_time_of_day"),
          tz_id: fd.get("tz_id"),
        }),
      });
      (e.currentTarget as HTMLFormElement).reset();
      reload();
    } catch (err: unknown) {
      setError((err as Error).message);
    }
  }

  return (
    <main className="min-h-screen bg-zinc-50 px-6 py-10">
      <div className="mx-auto max-w-5xl space-y-8">
        <header className="flex items-center justify-between">
          <h1 className="text-2xl font-semibold text-zinc-900">Dashboard</h1>
          <button onClick={() => { logout(); window.location.href = "/login"; }}
                  className="text-sm text-zinc-600 hover:text-zinc-900">ログアウト</button>
        </header>

        {error && <p data-testid="dashboard-error" className="rounded bg-rose-50 px-3 py-2 text-sm text-rose-700">{error}</p>}

        <Section title="Event types">
          <form onSubmit={createEventType} className="grid gap-3 sm:grid-cols-4 mb-4" data-testid="event-type-form">
            <input name="slug" placeholder="slug (kebab-case)" required className="rounded border border-zinc-300 px-3 py-2 text-sm" data-testid="et-slug" />
            <input name="title" placeholder="title" required className="rounded border border-zinc-300 px-3 py-2 text-sm" data-testid="et-title" />
            <input name="duration_minutes" type="number" min="15" defaultValue="30" required className="rounded border border-zinc-300 px-3 py-2 text-sm" data-testid="et-duration" />
            <button type="submit" className="rounded bg-emerald-600 py-2 text-sm font-semibold text-white hover:bg-emerald-700" data-testid="et-submit">作成</button>
          </form>
          <ul className="divide-y divide-zinc-200 rounded border border-zinc-200 bg-white">
            {eventTypes?.map((et) => (
              <li key={et.id} className="flex items-center justify-between px-4 py-2 text-sm" data-testid={`et-row-${et.id}`}>
                <span><b>{et.title}</b> <code className="ml-2 text-xs text-zinc-500">/{et.slug}</code></span>
                <span className="text-zinc-500">{et.duration_minutes} min</span>
              </li>
            ))}
            {eventTypes && eventTypes.length === 0 && <li className="px-4 py-3 text-sm text-zinc-500">(まだ event_type がありません)</li>}
          </ul>
        </Section>

        <Section title="Availability rules">
          <form onSubmit={createRule} className="grid gap-3 sm:grid-cols-5 mb-4" data-testid="rule-form">
            <input name="rrule" defaultValue="FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR" required className="rounded border border-zinc-300 px-3 py-2 text-sm" data-testid="rule-rrule" />
            <input name="start_time_of_day" defaultValue="09:00:00" required className="rounded border border-zinc-300 px-3 py-2 text-sm" data-testid="rule-start" />
            <input name="end_time_of_day" defaultValue="17:00:00" required className="rounded border border-zinc-300 px-3 py-2 text-sm" data-testid="rule-end" />
            <input name="tz_id" defaultValue="Asia/Tokyo" required className="rounded border border-zinc-300 px-3 py-2 text-sm" data-testid="rule-tz" />
            <button type="submit" className="rounded bg-emerald-600 py-2 text-sm font-semibold text-white hover:bg-emerald-700" data-testid="rule-submit">追加</button>
          </form>
          <ul className="divide-y divide-zinc-200 rounded border border-zinc-200 bg-white">
            {rules?.map((r) => (
              <li key={r.id} className="px-4 py-2 text-sm">
                <code className="text-xs text-zinc-500">{r.rrule}</code> · {r.start_time_of_day}–{r.end_time_of_day} · {r.tz_id}
              </li>
            ))}
            {rules && rules.length === 0 && <li className="px-4 py-3 text-sm text-zinc-500">(まだ availability_rule がありません)</li>}
          </ul>
        </Section>

        <Section title="受信予約">
          <ul className="divide-y divide-zinc-200 rounded border border-zinc-200 bg-white">
            {bookings?.map((b) => (
              <li key={b.id} className="flex items-center justify-between px-4 py-2 text-sm">
                <span>{new Date(b.start_at).toLocaleString()} – {new Date(b.end_at).toLocaleString()}</span>
                <span className="text-zinc-500">{b.invitee_email} <span className="ml-2 rounded bg-zinc-100 px-2 py-0.5 text-xs">{b.status}</span></span>
              </li>
            ))}
            {bookings && bookings.length === 0 && <li className="px-4 py-3 text-sm text-zinc-500">(まだ予約がありません)</li>}
          </ul>
        </Section>
      </div>
    </main>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section>
      <h2 className="mb-3 text-lg font-semibold text-zinc-900">{title}</h2>
      {children}
    </section>
  );
}
