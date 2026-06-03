"use client";

import { useCallback, useEffect, useState } from "react";
import { AuthGuard } from "@/components/AuthGuard";
import {
  cancelTrip,
  createTrip,
  fetchDemand,
  fetchTrip,
  type ApiTrip,
  type DemandForecast,
} from "@/lib/api";
import { LOCATIONS, locationById, nearestLabel } from "@/lib/locations";

// backend で実際に駆動される状態は driver_accepted まで (Phase 4-2)。
// それ以降 (arriving..completed) は将来のために map だけ用意しておく。
const STOP_POLL = new Set(["driver_accepted", "completed", "canceled"]);

function statusMeta(status: string): { label: string; color: string } {
  switch (status) {
    case "requested":
      return { label: "リクエスト受付", color: "var(--status-pending)" };
    case "matching":
      return { label: "ドライバを探索中…", color: "var(--status-pending)" };
    case "driver_accepted":
      return { label: "ドライバ確定 🎉", color: "var(--status-active)" };
    case "arriving":
      return { label: "ドライバ向かっています", color: "var(--status-active)" };
    case "arrived":
      return { label: "ドライバ到着", color: "var(--status-active)" };
    case "in_trip":
      return { label: "走行中", color: "var(--status-active)" };
    case "completed":
      return { label: "完了", color: "var(--status-dead)" };
    case "canceled":
      return { label: "キャンセル", color: "var(--status-dead)" };
    default:
      return { label: status, color: "var(--status-dead)" };
  }
}

function RiderConsole() {
  const [pickupId, setPickupId] = useState("shibuya");
  const [dropoffId, setDropoffId] = useState("shinjuku");
  const [trip, setTrip] = useState<ApiTrip | null>(null);
  const [eta, setEta] = useState<number | null>(null);
  const [surge, setSurge] = useState<DemandForecast | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // pickup の surge を表示 (ai-worker 境界 / degrade 安全)
  useEffect(() => {
    const p = locationById(pickupId);
    if (!p) return;
    let active = true;
    fetchDemand(p.lat, p.lng)
      .then((d) => active && setSurge(d))
      .catch(() => active && setSurge(null));
    return () => {
      active = false;
    };
  }, [pickupId]);

  // trip が active な間 GET /trips/:id を poll する。
  // driver_accepted / 終端に達したら停止 (status 変化で effect 再実行)。
  useEffect(() => {
    if (!trip || STOP_POLL.has(trip.status)) return;
    const id = trip.id;
    const timer = setTimeout(async () => {
      try {
        const { trip: fresh } = await fetchTrip(id);
        setTrip(fresh);
      } catch (err) {
        setError(err instanceof Error ? err.message : "poll failed");
      }
    }, 1500);
    return () => clearTimeout(timer);
  }, [trip]);

  const request = useCallback(async () => {
    const p = locationById(pickupId);
    const d = locationById(dropoffId);
    if (!p || !d) return;
    setBusy(true);
    setError(null);
    try {
      const res = await createTrip({
        pickup_lat: p.lat,
        pickup_lng: p.lng,
        dropoff_lat: d.lat,
        dropoff_lng: d.lng,
      });
      setTrip(res.trip);
      setEta(res.eta_seconds);
    } catch (err) {
      setError(err instanceof Error ? err.message : "request failed");
    } finally {
      setBusy(false);
    }
  }, [pickupId, dropoffId]);

  const cancel = useCallback(async () => {
    if (!trip) return;
    setBusy(true);
    setError(null);
    try {
      const { trip: fresh } = await cancelTrip(trip.id);
      setTrip(fresh);
    } catch (err) {
      setError(err instanceof Error ? err.message : "cancel failed");
    } finally {
      setBusy(false);
    }
  }, [trip]);

  const reset = () => {
    setTrip(null);
    setEta(null);
    setError(null);
  };

  const meta = trip ? statusMeta(trip.status) : null;
  const canCancel =
    trip &&
    !["completed", "canceled", "in_trip", "driver_accepted"].includes(
      trip.status,
    );
  const selectCls =
    "w-full bg-[var(--bg-elevated)] border border-[var(--border-strong)] rounded-md px-3 h-9 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)]";

  return (
    <div className="max-w-md mx-auto space-y-5">
      <h1 className="text-2xl font-bold tracking-tight">配車をリクエスト</h1>

      {!trip && (
        <div className="bg-[var(--panel)] border border-[var(--border)] shadow-sm rounded-[var(--radius)] p-5 space-y-4">
          <div>
            <label htmlFor="pickup" className="block text-sm mb-1 text-[var(--fg-muted)]">
              pickup
            </label>
            <select
              id="pickup"
              value={pickupId}
              onChange={(e) => setPickupId(e.target.value)}
              className={selectCls}
            >
              {LOCATIONS.map((l) => (
                <option key={l.id} value={l.id}>
                  {l.label}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label htmlFor="dropoff" className="block text-sm mb-1 text-[var(--fg-muted)]">
              dropoff
            </label>
            <select
              id="dropoff"
              value={dropoffId}
              onChange={(e) => setDropoffId(e.target.value)}
              className={selectCls}
            >
              {LOCATIONS.map((l) => (
                <option key={l.id} value={l.id}>
                  {l.label}
                </option>
              ))}
            </select>
          </div>

          {surge && (
            <p className="text-xs text-[var(--fg-muted)]">
              需要 {(surge.demand_index * 100).toFixed(0)}% / surge ×
              {surge.surge_multiplier.toFixed(2)}
              {surge.degraded && " (ai-worker degraded)"}
            </p>
          )}

          <button
            type="button"
            onClick={request}
            disabled={busy}
            className="w-full h-9 rounded-md bg-[var(--accent)] text-[var(--accent-fg)] hover:bg-[var(--accent-hover)] font-medium transition-colors disabled:opacity-50"
          >
            {busy ? "..." : "Request ride"}
          </button>
        </div>
      )}

      {trip && meta && (
        <div className="bg-[var(--panel)] border border-[var(--border)] shadow-sm rounded-[var(--radius)] p-5 space-y-3">
          <div className="flex items-center justify-between">
            <span className="text-xs text-[var(--fg-muted)]">trip #{trip.id}</span>
            <span
              data-testid="trip-status"
              data-status={trip.status}
              className="text-sm font-semibold"
              style={{ color: meta.color }}
            >
              {meta.label}
            </span>
          </div>
          <dl className="text-sm space-y-1">
            <Row k="pickup" v={nearestLabel(trip.pickup_lat, trip.pickup_lng)} />
            <Row k="dropoff" v={nearestLabel(trip.dropoff_lat, trip.dropoff_lng)} />
            <Row
              k="ETA"
              v={eta == null ? "— (ai-worker degraded)" : `${eta} 秒`}
            />
            {trip.driver_id != null && (
              <Row k="driver" v={`#${trip.driver_id}`} testid="driver-id" />
            )}
            {trip.canceled_reason && (
              <Row k="canceled" v={trip.canceled_reason} />
            )}
          </dl>

          {trip.status === "matching" && (
            <p className="text-xs text-[var(--fg-subtle)]">
              poll 中… driver が accept すると driver_accepted に変わります。
            </p>
          )}

          <div className="flex gap-2 pt-1">
            {canCancel && (
              <button
                type="button"
                onClick={cancel}
                disabled={busy}
                className="flex-1 h-9 rounded-md border border-[var(--border-strong)] text-[var(--fg-muted)] hover:bg-[var(--bg-subtle)] transition-colors disabled:opacity-50"
              >
                cancel
              </button>
            )}
            {STOP_POLL.has(trip.status) && (
              <button
                type="button"
                onClick={reset}
                className="flex-1 h-9 rounded-md bg-[var(--accent)] text-[var(--accent-fg)] hover:bg-[var(--accent-hover)] font-medium transition-colors"
              >
                new ride
              </button>
            )}
          </div>
        </div>
      )}

      {error && <p className="text-sm text-red-600">{error}</p>}
    </div>
  );
}

function Row({ k, v, testid }: { k: string; v: string; testid?: string }) {
  return (
    <div className="flex justify-between gap-4">
      <dt className="text-[var(--fg-muted)]">{k}</dt>
      <dd data-testid={testid} className="font-medium text-right">
        {v}
      </dd>
    </div>
  );
}

export default function RiderPage() {
  return (
    <AuthGuard requiredRole="rider">{() => <RiderConsole />}</AuthGuard>
  );
}
