"use client";

import { use, useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { Subscription } from "@rails/actioncable";
import { getToken, api } from "@/lib/api";
import { fetchMe } from "@/lib/auth";
import { fetchSnapshot } from "@/lib/documents";
import { getCableConsumer } from "@/lib/cable";
import { applyOp, num, type Op, type Shape } from "@/lib/crdt";

type Cursor = { name: string; x: number; y: number };
const COLORS = ["#7c3aed", "#db2777", "#0891b2", "#16a34a", "#ea580c", "#2563eb"];
const colorFor = (id: number) => COLORS[id % COLORS.length];

export default function EditorPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const docId = Number(id);
  const router = useRouter();

  const [shapes, setShapes] = useState<Map<string, Shape>>(new Map());
  const [selected, setSelected] = useState<string | null>(null);
  const [cursors, setCursors] = useState<Map<number, Cursor>>(new Map());
  const [role, setRole] = useState<string>("");
  const [ready, setReady] = useState(false);
  const [connected, setConnected] = useState(false);

  const meId = useRef<number>(0);
  const lamport = useRef<number>(0);
  const sub = useRef<Subscription | null>(null);
  const drag = useRef<{ shapeId: string; dx: number; dy: number } | null>(null);
  const lastCursorSent = useRef<number>(0);

  const canEdit = role === "owner" || role === "editor";

  const rerender = useCallback((mut: (m: Map<string, Shape>) => void) => {
    setShapes((prev) => {
      const next = new Map(prev);
      mut(next);
      return next;
    });
  }, []);

  // 受信 op を LWW 適用 (server echo / 他者の op)。lamport を進める。
  const onOperation = useCallback((op: Op) => {
    lamport.current = Math.max(lamport.current, op.lamport);
    rerender((m) => applyOp(m, op));
  }, [rerender]);

  // ローカル編集: lamport++ → 楽観適用 → server へ送信 (server で再 LWW + broadcast)。
  const emit = useCallback((shapeId: string, opType: Op["op_type"], payload: Op["payload"]) => {
    if (!canEdit) return;
    lamport.current += 1;
    const op: Op = { shape_id: shapeId, op_type: opType, payload, lamport: lamport.current, actor_id: meId.current };
    rerender((m) => applyOp(m, op));
    sub.current?.perform("apply_operation", op);
  }, [canEdit, rerender]);

  useEffect(() => {
    if (!getToken()) {
      router.replace("/login");
      return;
    }
    let active = true;

    (async () => {
      const me = await fetchMe().catch(() => null);
      if (!me) return router.replace("/login");
      meId.current = me.id;

      const snap = await fetchSnapshot(docId);
      if (!active) return;
      setRole(snap.document.role);
      lamport.current = snap.version;
      const m = new Map<string, Shape>();
      for (const o of snap.objects) {
        m.set(o.shape_id, { shape_id: o.shape_id, kind: o.kind, props: o.props, prop_clocks: {}, deleted: o.deleted });
      }
      setShapes(m);
      setReady(true);

      const channel = getCableConsumer().subscriptions.create(
        { channel: "DocumentChannel", document_id: docId },
        {
          connected() {
            setConnected(true);
          },
          disconnected() {
            setConnected(false);
          },
          received(data: { type: string; op?: Op; actor_id?: number; name?: string; x?: number; y?: number }) {
            if (data.type === "operation" && data.op) onOperation(data.op);
            else if (data.type === "cursor" && data.actor_id !== undefined && data.actor_id !== meId.current) {
              setCursors((prev) => {
                const next = new Map(prev);
                next.set(data.actor_id!, { name: data.name ?? "", x: data.x ?? 0, y: data.y ?? 0 });
                return next;
              });
            }
          },
        },
      );
      sub.current = channel;
    })();

    return () => {
      active = false;
      sub.current?.unsubscribe();
      sub.current = null;
    };
  }, [docId, router, onOperation]);

  // ── ツールバー操作 ──────────────────────────────────────────────
  function addShape(kind: "rect" | "ellipse") {
    const n = shapes.size;
    const shapeId = crypto.randomUUID();
    emit(shapeId, "create", {
      kind,
      x: 40 + (n % 6) * 100,
      y: 40 + Math.floor(n / 6) * 80,
      w: 80,
      h: 60,
      fill: colorFor(meId.current),
    });
    setSelected(shapeId);
  }

  function deleteSelected() {
    if (selected) emit(selected, "delete", {});
  }

  async function autoLayout() {
    const res = await api(`/documents/${docId}/auto_layout`, {
      method: "POST",
      body: JSON.stringify({ mode: "align-left" }),
    });
    if (!res.ok) return;
    const body = (await res.json()) as { updates?: { id: string; x: number; y: number }[] };
    for (const u of body.updates ?? []) emit(u.id, "update", { x: u.x, y: u.y });
  }

  // ── ドラッグ移動 ────────────────────────────────────────────────
  function onShapePointerDown(e: React.PointerEvent, s: Shape) {
    e.stopPropagation();
    setSelected(s.shape_id);
    if (!canEdit) return;
    drag.current = { shapeId: s.shape_id, dx: e.clientX - num(s, "x"), dy: e.clientY - num(s, "y") };
    (e.target as Element).setPointerCapture?.(e.pointerId);
  }

  function onSvgPointerMove(e: React.PointerEvent) {
    // cursor を throttle して fan-out (ephemeral)。
    const now = e.timeStamp;
    const rect = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    if (now - lastCursorSent.current > 50) {
      lastCursorSent.current = now;
      sub.current?.perform("cursor", { x, y });
    }
    // ドラッグ中は対象 shape を楽観移動 (clock は pointerup で stamp)。
    const d = drag.current;
    if (d) {
      rerender((m) => {
        const s = m.get(d.shapeId);
        if (s) {
          s.props.x = e.clientX - d.dx;
          s.props.y = e.clientY - d.dy;
        }
      });
    }
  }

  function onSvgPointerUp() {
    const d = drag.current;
    if (d) {
      const s = shapes.get(d.shapeId);
      if (s) emit(d.shapeId, "update", { x: num(s, "x"), y: num(s, "y") });
      drag.current = null;
    }
  }

  const alive = [...shapes.values()].filter((s) => !s.deleted);

  return (
    <main className="flex h-screen flex-col">
      <header className="flex items-center gap-3 border-b border-zinc-200 px-4 py-2">
        <button className="text-sm text-zinc-500 underline" onClick={() => router.push("/")}>← 一覧</button>
        <span className="text-xs text-zinc-400" data-testid="role">role: {role}</span>
        <span className="text-xs text-zinc-400" data-testid="cable-status">{connected ? "connected" : "connecting"}</span>
        <div className="ml-auto flex gap-2">
          <button data-testid="add-rect" disabled={!canEdit} onClick={() => addShape("rect")}
            className="rounded bg-violet-600 px-3 py-1 text-sm text-white disabled:opacity-40">+ 矩形</button>
          <button data-testid="add-ellipse" disabled={!canEdit} onClick={() => addShape("ellipse")}
            className="rounded bg-violet-600 px-3 py-1 text-sm text-white disabled:opacity-40">+ 楕円</button>
          <button data-testid="delete" disabled={!canEdit || !selected} onClick={deleteSelected}
            className="rounded bg-zinc-200 px-3 py-1 text-sm disabled:opacity-40">削除</button>
          <button data-testid="auto-layout" disabled={!canEdit} onClick={autoLayout}
            className="rounded bg-zinc-200 px-3 py-1 text-sm disabled:opacity-40">整列(左)</button>
        </div>
      </header>

      <div className="relative flex-1 overflow-hidden bg-zinc-50">
        <svg
          data-testid="canvas"
          className="h-full w-full touch-none"
          onPointerMove={onSvgPointerMove}
          onPointerUp={onSvgPointerUp}
          onPointerDown={() => setSelected(null)}
        >
          {alive.map((s) => {
            const x = num(s, "x");
            const y = num(s, "y");
            const w = num(s, "w", 80);
            const h = num(s, "h", 60);
            const fill = typeof s.props.fill === "string" ? s.props.fill : "#a1a1aa";
            const sel = selected === s.shape_id;
            const common = {
              "data-testid": `shape-${s.shape_id}`,
              "data-x": Math.round(x),
              "data-y": Math.round(y),
              fill,
              stroke: sel ? "#18181b" : "none",
              strokeWidth: 2,
              onPointerDown: (e: React.PointerEvent) => onShapePointerDown(e, s),
              style: { cursor: canEdit ? "move" : "default" },
            };
            return s.kind === "ellipse" ? (
              <ellipse key={s.shape_id} cx={x + w / 2} cy={y + h / 2} rx={w / 2} ry={h / 2} {...common} />
            ) : (
              <rect key={s.shape_id} x={x} y={y} width={w} height={h} rx={4} {...common} />
            );
          })}

          {[...cursors.entries()].map(([aid, c]) => (
            <g key={aid} transform={`translate(${c.x},${c.y})`} pointerEvents="none">
              <circle r={4} fill={colorFor(aid)} />
              <text x={8} y={4} fontSize={11} fill={colorFor(aid)}>{c.name}</text>
            </g>
          ))}
        </svg>
        {!ready && <div className="absolute inset-0 grid place-items-center text-zinc-400">読み込み中…</div>}
      </div>
    </main>
  );
}
