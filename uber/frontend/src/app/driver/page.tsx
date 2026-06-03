"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { AuthGuard } from "@/components/AuthGuard";
import { getToken } from "@/lib/api";
import { LOCATIONS, locationById, nearestLabel } from "@/lib/locations";
import { DriverGateway, type ConnState, type OfferMsg } from "@/lib/ws";

type DriverStatus = "offline" | "online" | "matched";

function DriverConsole() {
  const [onlineLocId, setOnlineLocId] = useState("shibuya");
  const [conn, setConn] = useState<ConnState | "idle">("idle");
  const [status, setStatus] = useState<DriverStatus>("offline");
  const [offer, setOffer] = useState<OfferMsg | null>(null);
  const [acceptedTripId, setAcceptedTripId] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const gwRef = useRef<DriverGateway | null>(null);

  // unmount 時に WS を畳む (markOffline が backend で走る)
  useEffect(() => {
    return () => gwRef.current?.close();
  }, []);

  const goOnline = useCallback(() => {
    const token = getToken();
    const loc = locationById(onlineLocId);
    if (!token || !loc) return;
    setError(null);
    setAcceptedTripId(null);
    const gw = new DriverGateway(token, {
      onHello: () => {
        gw.goOnline(loc.lat, loc.lng);
        setStatus("online");
      },
      onOffer: (m) => setOffer(m),
      onError: (m) => setError(m.message),
      onState: (s) => {
        setConn(s);
        if (s === "closed") {
          setStatus("offline");
          setOffer(null);
        }
      },
    });
    gwRef.current = gw;
    gw.connect();
  }, [onlineLocId]);

  const goOffline = useCallback(() => {
    gwRef.current?.goOffline();
    gwRef.current?.close();
    gwRef.current = null;
    setStatus("offline");
    setConn("idle");
    setOffer(null);
  }, []);

  const accept = useCallback(() => {
    if (!offer) return;
    gwRef.current?.accept(offer.trip_id);
    // backend は accept への ack を返さない (matcher へ routing するのみ) ので
    // ここでは楽観的に matched 表示にする。trip は driver_accepted に遷移済み。
    setAcceptedTripId(offer.trip_id);
    setStatus("matched");
    setOffer(null);
  }, [offer]);

  const reject = useCallback(() => {
    if (!offer) return;
    gwRef.current?.reject(offer.trip_id);
    setOffer(null);
  }, [offer]);

  const statusColor =
    status === "matched"
      ? "var(--status-active)"
      : status === "online"
        ? "var(--status-pending)"
        : "var(--status-dead)";
  const selectCls =
    "w-full bg-[var(--bg-elevated)] border border-[var(--border-strong)] rounded-md px-3 h-9 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)] disabled:opacity-50";

  return (
    <div className="max-w-md mx-auto space-y-5">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold tracking-tight">driver console</h1>
        <span
          data-testid="driver-status"
          data-status={status}
          className="text-sm font-semibold"
          style={{ color: statusColor }}
        >
          {status}
          {conn !== "idle" && conn !== "open" && (
            <span className="ml-1 text-[var(--fg-subtle)]">({conn})</span>
          )}
        </span>
      </div>

      <div className="bg-[var(--panel)] border border-[var(--border)] shadow-sm rounded-[var(--radius)] p-5 space-y-4">
        <div>
          <label htmlFor="loc" className="block text-sm mb-1 text-[var(--fg-muted)]">
            待機位置 (go online)
          </label>
          <select
            id="loc"
            value={onlineLocId}
            onChange={(e) => setOnlineLocId(e.target.value)}
            disabled={status !== "offline"}
            className={selectCls}
          >
            {LOCATIONS.map((l) => (
              <option key={l.id} value={l.id}>
                {l.label}
              </option>
            ))}
          </select>
        </div>

        {status === "offline" ? (
          <button
            type="button"
            onClick={goOnline}
            className="w-full h-9 rounded-md bg-[var(--accent)] text-[var(--accent-fg)] hover:bg-[var(--accent-hover)] font-medium transition-colors"
          >
            Go online
          </button>
        ) : (
          <button
            type="button"
            onClick={goOffline}
            className="w-full h-9 rounded-md border border-[var(--border-strong)] text-[var(--fg-muted)] hover:bg-[var(--bg-subtle)] transition-colors"
          >
            Go offline
          </button>
        )}
      </div>

      {status === "online" && !offer && (
        <p className="text-center text-sm text-[var(--fg-subtle)] py-6">
          offer を待機中… rider が同じエリアで配車要求すると届きます。
        </p>
      )}

      {offer && (
        <div
          data-testid="offer-card"
          className="bg-[var(--panel)] border-2 border-[var(--accent)] shadow rounded-[var(--radius)] p-5 space-y-3"
        >
          <div className="flex items-center justify-between">
            <span className="text-lg font-semibold">配車オファー</span>
            <span className="text-xs text-[var(--fg-muted)]">trip #{offer.trip_id}</span>
          </div>
          <dl className="text-sm space-y-1">
            <Row k="pickup" v={nearestLabel(offer.pickup_lat, offer.pickup_lng)} />
            <Row k="dropoff" v={nearestLabel(offer.dropoff_lat, offer.dropoff_lng)} />
          </dl>
          <div className="flex gap-2 pt-1">
            <button
              type="button"
              onClick={accept}
              data-testid="accept-btn"
              className="flex-1 h-9 rounded-md bg-[var(--accent)] text-[var(--accent-fg)] hover:bg-[var(--accent-hover)] font-medium transition-colors"
            >
              Accept
            </button>
            <button
              type="button"
              onClick={reject}
              className="flex-1 h-9 rounded-md border border-[var(--border-strong)] text-[var(--fg-muted)] hover:bg-[var(--bg-subtle)] transition-colors"
            >
              Reject
            </button>
          </div>
        </div>
      )}

      {acceptedTripId != null && (
        <div className="bg-[var(--panel)] border border-[var(--border)] shadow-sm rounded-[var(--radius)] p-5">
          <p className="text-sm">
            <span className="font-semibold" style={{ color: "var(--status-active)" }}>
              accepted
            </span>{" "}
            — trip #{acceptedTripId} を担当中 (compare-and-set で確定)。
          </p>
        </div>
      )}

      {error && <p className="text-sm text-red-600">{error}</p>}
    </div>
  );
}

function Row({ k, v }: { k: string; v: string }) {
  return (
    <div className="flex justify-between gap-4">
      <dt className="text-[var(--fg-muted)]">{k}</dt>
      <dd className="font-medium text-right">{v}</dd>
    </div>
  );
}

export default function DriverPage() {
  return (
    <AuthGuard requiredRole="driver">{() => <DriverConsole />}</AuthGuard>
  );
}
