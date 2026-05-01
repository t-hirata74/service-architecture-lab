type Props = { state: string };

const COLORS: Record<string, string> = {
  SUCCESS: "bg-emerald-100 text-emerald-800 border-emerald-300",
  FAILURE: "bg-rose-100 text-rose-800 border-rose-300",
  PENDING: "bg-amber-100 text-amber-800 border-amber-300",
  ERROR: "bg-rose-100 text-rose-800 border-rose-300",
  NONE: "bg-zinc-100 text-zinc-600 border-zinc-200",
};

export default function CheckBadge({ state }: Props) {
  const cls = COLORS[state] ?? COLORS.NONE;
  return (
    <span className={`text-xs px-2 py-0.5 rounded border font-mono ${cls}`}>{state}</span>
  );
}
