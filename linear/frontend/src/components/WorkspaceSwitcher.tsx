'use client';

import { useState } from 'react';
import { fetchWorkspaces, type WorkspaceListItem } from '@/lib/api';
import { setSession } from '@/lib/session';
import { useSync } from '@/lib/sync-provider';

/**
 * workspace 切替 (E1)。招待された workspace は op では届かない
 * (本人はまだ購読していない) ため、開いたタイミングで /auth/me から発見する。
 * 切替は session の workspace を書き換え → board が SyncProvider を remount。
 */
export function WorkspaceSwitcher() {
  const { session } = useSync();
  const [open, setOpen] = useState(false);
  const [list, setList] = useState<WorkspaceListItem[] | null>(null);

  const toggle = () => {
    const next = !open;
    setOpen(next);
    if (next) {
      void fetchWorkspaces()
        .then(setList)
        .catch(() => setList([]));
    }
  };

  return (
    <div className="relative">
      <button
        data-testid="workspace-switcher"
        onClick={toggle}
        className="rounded-md px-1 text-sm font-semibold hover:bg-zinc-100"
      >
        <span className="text-indigo-600">▲</span> {session.workspace.name}{' '}
        <span className="text-zinc-400">▾</span>
      </button>
      {open && (
        <ul className="absolute top-full left-0 z-30 mt-1 w-60 rounded-md border border-zinc-200 bg-white py-1 shadow-lg">
          {list === null && (
            <li className="px-3 py-2 text-xs text-zinc-400">読み込み中…</li>
          )}
          {list?.map((w) => (
            <li key={w.id}>
              <button
                data-testid="workspace-option"
                onClick={() => {
                  setOpen(false);
                  setSession({
                    ...session,
                    workspace: { id: w.id, name: w.name, urlKey: w.urlKey },
                  });
                }}
                className={`flex w-full items-center justify-between px-3 py-1.5 text-left text-sm hover:bg-zinc-50 ${
                  w.id === session.workspace.id ? 'text-indigo-700' : ''
                }`}
              >
                <span>{w.name}</span>
                <span className="text-[10px] text-zinc-400">{w.role}</span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
