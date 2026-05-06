// ADR 0001 (modular monolith) を視覚化するページ。Backend を叩かない静的可視化。
// gif 撮影では「5 Engine + 依存方向 + packwerk pass」の絵を撮る。

const ENGINES = [
  { id: "core",      desc: "Shop / Account / User / Tenant resolver", color: "bg-zinc-900",   layer: 1 },
  { id: "catalog",   desc: "Product / Variant",                       color: "bg-indigo-700", layer: 2 },
  { id: "inventory", desc: "Location / InventoryLevel / Movement",    color: "bg-amber-700",  layer: 2 },
  { id: "orders",    desc: "Cart / Order / Checkout",                  color: "bg-emerald-700", layer: 3 },
  { id: "apps",      desc: "App / Installation / WebhookDelivery",    color: "bg-rose-700",   layer: 3 },
] as const;

// 許可された依存方向 (ADR 0001 / packwerk が CI で強制)。
const DEPS: Array<[string, string]> = [
  ["catalog", "core"],
  ["inventory", "core"],
  ["inventory", "catalog"],
  ["orders", "core"],
  ["orders", "catalog"],
  ["orders", "inventory"],
  ["apps", "core"],
  ["apps", "orders"],
];

const FORBIDDEN: Array<[string, string, string]> = [
  ["core", "catalog", "core は他 Engine に依存しない (循環防止)"],
  ["catalog", "orders", "下位 Engine から上位 Engine への逆参照"],
  ["orders", "apps", "ActiveSupport::Notifications で dependency inversion"],
];

export default function SystemPage() {
  const layered = [1, 2, 3].map((layer) => ENGINES.filter((e) => e.layer === layer));

  return (
    <div className="space-y-6" data-testid="system-page">
      <header className="space-y-1">
        <h2 className="text-2xl font-bold tracking-tight">system / engines</h2>
        <p className="text-sm text-zinc-500">
          ADR 0001 — Rails Engine 5 つ + packwerk で依存方向を CI 強制
        </p>
      </header>

      {/* 5 Engines layered */}
      <section className="bg-white border border-zinc-200 rounded-lg p-5 space-y-4">
        <div className="flex items-center justify-between">
          <h3 className="text-sm font-semibold tracking-tight">modular monolith (5 engines, layered)</h3>
          <span className="inline-flex items-center gap-1.5 text-xs bg-emerald-50 text-emerald-800 border border-emerald-200 rounded-full px-2.5 py-0.5">
            <span className="w-1.5 h-1.5 bg-emerald-600 rounded-full" />
            packwerk: 0 violations
          </span>
        </div>

        <div className="space-y-3">
          {layered.map((row, i) => (
            <div key={i} className="flex gap-2">
              <div className="text-[10px] font-mono text-zinc-400 w-12 pt-3">layer {i + 1}</div>
              <div className="flex-1 grid gap-2" style={{ gridTemplateColumns: `repeat(${row.length}, minmax(0, 1fr))` }}>
                {row.map((e) => (
                  <div
                    key={e.id}
                    data-testid={`engine-${e.id}`}
                    className={`${e.color} text-white rounded-md px-3 py-2.5 shadow-sm`}
                  >
                    <div className="font-mono text-sm font-semibold">{e.id}</div>
                    <div className="text-[11px] opacity-90 mt-0.5">{e.desc}</div>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* Allowed dependencies */}
      <section className="bg-white border border-zinc-200 rounded-lg p-5 space-y-3">
        <h3 className="text-sm font-semibold tracking-tight">allowed dependencies (declared in package.yml)</h3>
        <ul className="grid sm:grid-cols-2 gap-1.5 text-xs font-mono text-zinc-700">
          {DEPS.map(([from, to]) => (
            <li key={`${from}->${to}`} className="flex items-center gap-2">
              <span className="text-emerald-700">✓</span>
              <span>{from}</span>
              <span className="text-zinc-400">→</span>
              <span>{to}</span>
            </li>
          ))}
        </ul>
      </section>

      {/* Forbidden / inverted */}
      <section className="bg-white border border-zinc-200 rounded-lg p-5 space-y-3">
        <h3 className="text-sm font-semibold tracking-tight">forbidden (CI fails)</h3>
        <ul className="space-y-1.5 text-xs">
          {FORBIDDEN.map(([from, to, why]) => (
            <li key={`${from}->${to}`} className="flex items-start gap-2">
              <span className="text-rose-700 font-bold">✗</span>
              <span className="font-mono text-zinc-700">
                {from} <span className="text-zinc-400">→</span> {to}
              </span>
              <span className="text-zinc-500">— {why}</span>
            </li>
          ))}
        </ul>
        <div className="text-[11px] text-zinc-500 pt-2 border-t border-zinc-200">
          orders → apps の本来の方向は <code className="font-mono">ActiveSupport::Notifications</code> で逆転 (orders.order_created を apps が subscribe)。
        </div>
      </section>
    </div>
  );
}
