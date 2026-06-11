'use client';

import { useMemo, useState } from 'react';
import type { Team } from '@linear/shared';
import { useSync } from '@/lib/sync-provider';
import { identifier } from '@/lib/issue-utils';

interface PaletteItem {
  key: string;
  label: string;
  hint?: string;
  run: () => void;
}

interface PaletteProps {
  open: boolean;
  team: Team;
  onClose: () => void;
  onNewIssue: () => void;
  onSelectTeam: (teamId: number) => void;
  onSelectIssue: (issueId: number) => void;
}

/**
 * Cmd+K palette。issue 検索は IndexedDB 由来のローカル snapshot に対して行うため
 * server 往復ゼロで即応答する (local-first の体感デモ)。
 * open のたびに inner を mount し直すことで query/cursor を初期化する
 * (effect での setState を避ける / react-hooks v6)。
 */
export function CommandPalette(props: PaletteProps) {
  if (!props.open) return null;
  return <PaletteInner {...props} />;
}

function PaletteInner({
  team,
  onClose,
  onNewIssue,
  onSelectTeam,
  onSelectIssue,
}: PaletteProps) {
  const { state } = useSync();
  const [query, setQuery] = useState('');
  const [cursor, setCursor] = useState(0);

  const items = useMemo((): PaletteItem[] => {
    const q = query.trim().toLowerCase();
    const actions: PaletteItem[] = [
      {
        key: 'action-new-issue',
        label: '新しい issue を作成',
        hint: 'action',
        run: onNewIssue,
      },
      ...Object.values(state.teams)
        .filter((t) => t.id !== team.id)
        .map((t) => ({
          key: `team-${t.id}`,
          label: `チーム ${t.key} (${t.name}) へ移動`,
          hint: 'team',
          run: () => onSelectTeam(t.id),
        })),
    ].filter((a) => q === '' || a.label.toLowerCase().includes(q));

    const issues = Object.values(state.issues)
      .filter((i) => q !== '' && i.title.toLowerCase().includes(q))
      .slice(0, 8)
      .map((i) => ({
        key: `issue-${i.id}`,
        label: i.title,
        hint: identifier(i, state.teams[i.teamId]),
        run: () => onSelectIssue(i.id),
      }));

    return [...actions, ...issues];
  }, [query, state, team.id, onNewIssue, onSelectTeam, onSelectIssue]);

  return (
    <div
      className="fixed inset-0 z-30 flex items-start justify-center bg-zinc-900/30 pt-28"
      onClick={onClose}
    >
      <div
        data-testid="command-palette"
        onClick={(e) => e.stopPropagation()}
        className="w-130 overflow-hidden rounded-xl border border-zinc-200 bg-white shadow-xl"
      >
        <input
          data-testid="command-palette-input"
          autoFocus
          className="w-full border-b border-zinc-100 px-4 py-3 text-sm outline-none"
          placeholder="コマンドまたは issue タイトルを検索…"
          value={query}
          onChange={(e) => {
            setQuery(e.target.value);
            setCursor(0);
          }}
          onKeyDown={(e) => {
            if (e.key === 'ArrowDown') setCursor((c) => Math.min(c + 1, items.length - 1));
            if (e.key === 'ArrowUp') setCursor((c) => Math.max(c - 1, 0));
            if (e.key === 'Enter') items[cursor]?.run();
          }}
        />
        <ul className="max-h-72 overflow-y-auto py-1">
          {items.length === 0 && (
            <li className="px-4 py-2 text-xs text-zinc-400">該当なし</li>
          )}
          {items.map((item, i) => (
            <li key={item.key}>
              <button
                data-testid="command-palette-item"
                onClick={item.run}
                onMouseEnter={() => setCursor(i)}
                className={`flex w-full items-center justify-between px-4 py-2 text-left text-sm ${
                  i === cursor ? 'bg-indigo-50 text-indigo-900' : ''
                }`}
              >
                <span>{item.label}</span>
                {item.hint && (
                  <span className="text-[11px] text-zinc-400">{item.hint}</span>
                )}
              </button>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
