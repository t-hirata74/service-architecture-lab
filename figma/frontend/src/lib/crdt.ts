// client 側 LWW-CRDT。backend の OperationApplier (ADR 0001) と同じ規則で適用することで、
// 楽観適用 (local) と server echo (broadcast) を混ぜても全 client が同一状態に収束する。

export type Clock = { l: number; a: number };

export type Shape = {
  shape_id: string;
  kind: string;
  props: Record<string, number | string | boolean>;
  prop_clocks: Record<string, Clock>;
  deleted: boolean;
};

export type Op = {
  shape_id: string;
  op_type: "create" | "update" | "delete";
  payload: Record<string, number | string | boolean>;
  lamport: number;
  actor_id: number;
};

// incoming (lamport, actor) が stored clock より新しいか。tie は actor_id (server と同一規則)。
export function newer(l: number, a: number, stored?: Clock): boolean {
  if (!stored) return true;
  if (l !== stored.l) return l > stored.l;
  return a > stored.a;
}

// op を shapes マップに LWW 適用する (破壊的)。backend OperationApplier#materialize! のミラー。
export function applyOp(shapes: Map<string, Shape>, op: Op): void {
  let s = shapes.get(op.shape_id);
  if (!s) {
    const kind = op.op_type === "create" && typeof op.payload.kind === "string" ? op.payload.kind : "rect";
    s = { shape_id: op.shape_id, kind, props: {}, prop_clocks: {}, deleted: false };
    shapes.set(op.shape_id, s);
  } else if (op.op_type === "create" && typeof op.payload.kind === "string") {
    s.kind = op.payload.kind; // create は kind の唯一の設定者
  }

  const lww: Record<string, number | string | boolean> = { ...op.payload };
  delete lww.kind;
  if (op.op_type === "delete") lww.deleted = true;

  for (const [k, v] of Object.entries(lww)) {
    if (newer(op.lamport, op.actor_id, s.prop_clocks[k])) {
      s.props[k] = v;
      s.prop_clocks[k] = { l: op.lamport, a: op.actor_id };
    }
  }
  s.deleted = s.props.deleted === true;
}

// 数値プロパティ取得ヘルパ。
export function num(s: Shape, key: string, fallback = 0): number {
  const v = s.props[key];
  return typeof v === "number" ? v : fallback;
}
