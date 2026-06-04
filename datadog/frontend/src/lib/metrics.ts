import { api } from "./api";

export type SeriesMeta = {
  series_key: string;
  metric_name: string;
  tags: string;
  type: string;
};

export type Point = {
  ts: string;
  count: number;
  sum: number;
  min: number;
  max: number;
  last: number;
  avg: number;
};

export type QuerySeries = { series_key: string; tags: unknown; points: Point[] };

export type Stats = {
  dropped_ingest: number;
  dropped_cardinality: number;
  flush_errors: number;
  active_series: number;
};

export type AlertEvent = {
  id: number;
  rule_id: number;
  state: string;
  value: number;
  created_at: string;
};

export async function listMetrics(): Promise<SeriesMeta[]> {
  const res = await api("/metrics");
  if (!res.ok) throw new Error("metrics 取得に失敗しました");
  return (await res.json()).series ?? [];
}

export async function query(metric: string): Promise<QuerySeries[]> {
  const res = await api(`/query?metric=${encodeURIComponent(metric)}`);
  if (!res.ok) throw new Error("query に失敗しました");
  return (await res.json()).series ?? [];
}

export async function fetchStats(): Promise<Stats> {
  const res = await api("/stats");
  if (!res.ok) throw new Error("stats に失敗しました");
  return res.json();
}

export async function fetchAlertEvents(): Promise<AlertEvent[]> {
  const res = await api("/alerts/events?limit=20");
  if (!res.ok) throw new Error("alerts に失敗しました");
  return (await res.json()).events ?? [];
}
