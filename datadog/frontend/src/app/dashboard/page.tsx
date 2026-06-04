"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { getToken } from "@/lib/api";
import { fetchMe, logout } from "@/lib/auth";
import {
  fetchAlertEvents,
  fetchStats,
  listMetrics,
  query,
  type AlertEvent,
  type QuerySeries,
  type Stats,
} from "@/lib/metrics";

const COLORS = ["#7b61ff", "#13c2c2", "#52c41a", "#fa8c16", "#f5222d", "#eb2f96"];

export default function Dashboard() {
  const router = useRouter();
  const [ready, setReady] = useState(false);
  const [metrics, setMetrics] = useState<string[]>([]);
  const [metric, setMetric] = useState<string>("");
  const [series, setSeries] = useState<QuerySeries[]>([]);
  const [stats, setStats] = useState<Stats | null>(null);
  const [alerts, setAlerts] = useState<AlertEvent[]>([]);
  const metricRef = useRef("");

  const refresh = useCallback(async () => {
    try {
      const ms = await listMetrics();
      const names = Array.from(new Set(ms.map((m) => m.metric_name)));
      setMetrics(names);
      let cur = metricRef.current;
      if (!cur && names.length) {
        cur = names[0];
        metricRef.current = cur;
        setMetric(cur);
      }
      if (cur) setSeries(await query(cur));
      setStats(await fetchStats());
      setAlerts(await fetchAlertEvents());
    } catch {
      /* poll エラーは握りつぶす (次の tick で再試行) */
    }
  }, []);

  useEffect(() => {
    if (!getToken()) {
      router.replace("/login");
      return;
    }
    fetchMe()
      .then(() => setReady(true))
      .catch(() => router.replace("/login"));
  }, [router]);

  useEffect(() => {
    if (!ready) return;
    refresh();
    const id = setInterval(refresh, 3000);
    return () => clearInterval(id);
  }, [ready, refresh]);

  function selectMetric(m: string) {
    metricRef.current = m;
    setMetric(m);
    query(m).then(setSeries).catch(() => undefined);
  }

  if (!ready) return <main className="p-8 text-zinc-500">読み込み中…</main>;

  return (
    <main className="mx-auto max-w-4xl px-6 py-8">
      <header className="mb-6 flex items-center justify-between">
        <h1 className="text-xl font-semibold">datadog-lab dashboard</h1>
        <button className="text-sm text-zinc-400 underline" onClick={() => { logout(); router.replace("/login"); }}>
          ログアウト
        </button>
      </header>

      <section className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-4" data-testid="stats">
        <Stat label="active series" value={stats?.active_series} />
        <Stat label="dropped (ingest)" value={stats?.dropped_ingest} />
        <Stat label="dropped (cardinality)" value={stats?.dropped_cardinality} />
        <Stat label="flush errors" value={stats?.flush_errors} />
      </section>

      <section className="mb-6">
        <div className="mb-2 flex flex-wrap items-center gap-2">
          <span className="text-sm text-zinc-400">metric:</span>
          {metrics.length === 0 && <span className="text-sm text-zinc-600" data-testid="no-metrics">（まだメトリクスがありません）</span>}
          {metrics.map((m) => (
            <button
              key={m}
              data-testid={`metric-${m}`}
              onClick={() => selectMetric(m)}
              className={`rounded px-2 py-1 text-xs ${m === metric ? "bg-violet-600 text-white" : "bg-zinc-800 text-zinc-300"}`}
            >
              {m}
            </button>
          ))}
        </div>
        <Chart series={series} />
      </section>

      <section>
        <h2 className="mb-2 text-sm font-semibold text-zinc-300">recent alerts</h2>
        <ul className="divide-y divide-zinc-800 text-sm" data-testid="alerts">
          {alerts.length === 0 && <li className="py-2 text-zinc-600">なし</li>}
          {alerts.map((a) => (
            <li key={a.id} className="flex justify-between py-2">
              <span className={a.state === "firing" ? "text-red-400" : a.state === "resolved" ? "text-green-400" : "text-yellow-400"}>
                {a.state}
              </span>
              <span className="text-zinc-500">rule #{a.rule_id} · {a.value.toFixed(2)} · {a.created_at}</span>
            </li>
          ))}
        </ul>
      </section>
    </main>
  );
}

function Stat({ label, value }: { label: string; value?: number }) {
  return (
    <div className="rounded border border-zinc-800 bg-zinc-900/50 p-3">
      <div className="text-xs text-zinc-500">{label}</div>
      <div className="text-lg font-semibold">{value ?? "—"}</div>
    </div>
  );
}

function Chart({ series }: { series: QuerySeries[] }) {
  const W = 720;
  const H = 240;
  const pad = 28;

  const allPts = series.flatMap((s) => s.points);
  if (allPts.length === 0) {
    return (
      <div className="grid h-[240px] place-items-center rounded border border-zinc-800 text-zinc-600" data-testid="chart-empty">
        データなし（メトリクスを投入すると表示されます）
      </div>
    );
  }

  const ys = allPts.map((p) => p.avg);
  const yMin = Math.min(...ys);
  const yMax = Math.max(...ys);
  const yRange = yMax - yMin || 1;
  const maxLen = Math.max(...series.map((s) => s.points.length));
  const xStep = maxLen > 1 ? (W - 2 * pad) / (maxLen - 1) : 0;
  const yOf = (v: number) => H - pad - ((v - yMin) / yRange) * (H - 2 * pad);

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full rounded border border-zinc-800 bg-zinc-900/50" data-testid="chart">
      {series.map((s, si) => {
        const color = COLORS[si % COLORS.length];
        const pts = s.points.map((p, i) => `${pad + i * xStep},${yOf(p.avg)}`).join(" ");
        return (
          <g key={s.series_key}>
            {s.points.length > 1 && <polyline points={pts} fill="none" stroke={color} strokeWidth={2} />}
            {s.points.map((p, i) => (
              <circle key={i} cx={pad + i * xStep} cy={yOf(p.avg)} r={3} fill={color} data-testid="datapoint" />
            ))}
          </g>
        );
      })}
      <text x={pad} y={16} fontSize={11} fill="#71717a">max {yMax.toFixed(2)}</text>
      <text x={pad} y={H - 8} fontSize={11} fill="#71717a">min {yMin.toFixed(2)}</text>
    </svg>
  );
}
