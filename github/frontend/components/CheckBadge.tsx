type Props = { state: string };

const COLORS: Record<string, string> = {
  SUCCESS: "bg-emerald-50 text-emerald-700 border-emerald-200",
  FAILURE: "bg-rose-50 text-rose-700 border-rose-200",
  PENDING: "bg-amber-50 text-amber-700 border-amber-200",
  ERROR:   "bg-rose-50 text-rose-700 border-rose-200",
  NONE:    "bg-[var(--bg-subtle)] text-[var(--fg-muted)] border-[var(--border)]",
};

const ICONS: Record<string, string> = {
  SUCCESS: "✓",
  FAILURE: "✕",
  PENDING: "●",
  ERROR:   "!",
  NONE:    "○",
};

export default function CheckBadge({ state }: Props) {
  const cls = COLORS[state] ?? COLORS.NONE;
  const icon = ICONS[state] ?? ICONS.NONE;
  return (
    <span
      className={`inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full border font-medium ${cls}`}
    >
      <span aria-hidden className="text-[10px] leading-none">{icon}</span>
      <span className="font-mono">{state}</span>
    </span>
  );
}
