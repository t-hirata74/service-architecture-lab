'use client';

import { useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { appendOrderKey } from '@linear/shared';
import type { Issue, WorkflowState } from '@linear/shared';
import { useSync } from '@/lib/sync-provider';
import { setSession } from '@/lib/session';
import { identifier, issuesInColumn, PRIORITIES } from '@/lib/issue-utils';
import { CommandPalette } from './CommandPalette';
import { IssueDetail } from './IssueDetail';
import { NewIssueDialog } from './NewIssueDialog';

export function Workspace() {
  const router = useRouter();
  const sync = useSync();
  const { state, status, online, pendingCount, lastSyncId, mutate, session } =
    sync;

  const teams = useMemo(
    () => Object.values(state.teams).sort((a, b) => a.id - b.id),
    [state.teams],
  );
  const [teamIdRaw, setTeamId] = useState<number | null>(null);
  const team = teams.find((t) => t.id === teamIdRaw) ?? teams[0];

  const [selectedIssueId, setSelectedIssueId] = useState<number | null>(null);
  const [newIssueStateId, setNewIssueStateId] = useState<number | null>(null);
  const [paletteOpen, setPaletteOpen] = useState(false);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        setPaletteOpen((v) => !v);
      }
      if (e.key === 'Escape') {
        setPaletteOpen(false);
        setSelectedIssueId(null);
        setNewIssueStateId(null);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  if (status !== 'ready' || !team) {
    return (
      <main className="flex min-h-screen items-center justify-center text-sm text-zinc-500">
        同期中…
      </main>
    );
  }

  const states = Object.values(state.states)
    .filter((s) => s.teamId === team.id)
    .sort((a, b) => a.position - b.position);

  const moveTo = (issue: Issue, target: WorkflowState) => {
    mutate({
      type: 'moveIssue',
      issueId: issue.id,
      stateId: target.id,
      sortOrder: appendOrderKey(state, team.id, target.id),
    });
  };

  return (
    <div className="flex h-screen flex-col">
      <header className="flex items-center gap-4 border-b border-zinc-200 bg-white px-4 py-2">
        <span className="text-sm font-semibold">
          <span className="text-indigo-600">▲</span> {session.workspace.name}
        </span>
        <nav className="flex gap-1">
          {teams.map((t) => (
            <button
              key={t.id}
              onClick={() => setTeamId(t.id)}
              className={`rounded-md px-2 py-1 text-xs font-medium ${
                t.id === team.id
                  ? 'bg-indigo-50 text-indigo-700'
                  : 'text-zinc-500 hover:bg-zinc-100'
              }`}
            >
              {t.key}
            </button>
          ))}
        </nav>
        <div className="ml-auto flex items-center gap-3 text-xs text-zinc-500">
          <span
            data-testid="sync-status"
            className={`rounded-full px-2 py-0.5 ${
              !online
                ? 'bg-amber-100 text-amber-800'
                : pendingCount > 0
                  ? 'bg-indigo-100 text-indigo-700'
                  : 'bg-zinc-100'
            }`}
          >
            {!online
              ? `オフライン${pendingCount > 0 ? ` (${pendingCount} 件保留)` : ''}`
              : pendingCount > 0
                ? `同期中 ${pendingCount} 件`
                : `同期済み #${lastSyncId}`}
          </span>
          <button
            onClick={() => setPaletteOpen(true)}
            className="rounded-md border border-zinc-200 px-2 py-0.5 hover:bg-zinc-50"
          >
            ⌘K
          </button>
          <span>{session.user.name}</span>
          <button
            onClick={() => {
              setSession(null);
              router.push('/login');
            }}
            className="text-zinc-400 hover:text-zinc-600"
          >
            ログアウト
          </button>
        </div>
      </header>

      {sync.errors.length > 0 && (
        <div className="border-b border-red-200 bg-red-50 px-4 py-1 text-xs text-red-700">
          {sync.errors[sync.errors.length - 1]}
        </div>
      )}

      <main className="flex flex-1 gap-3 overflow-x-auto p-4">
        {states.map((column) => {
          const issues = issuesInColumn(state, team.id, column.id);
          return (
            <section
              key={column.id}
              data-testid="board-column"
              data-column-name={column.name}
              className="flex w-64 shrink-0 flex-col rounded-lg bg-zinc-100/70"
            >
              <header className="flex items-center justify-between px-3 py-2">
                <h2 className="text-xs font-semibold text-zinc-600">
                  {column.name}
                  <span className="ml-1 font-normal text-zinc-400">
                    {issues.length}
                  </span>
                </h2>
                <button
                  data-testid={`new-issue-${column.name}`}
                  onClick={() => setNewIssueStateId(column.id)}
                  className="rounded px-1 text-zinc-400 hover:bg-zinc-200 hover:text-zinc-600"
                  title={`${column.name} に issue を追加`}
                >
                  ＋
                </button>
              </header>
              <div className="flex flex-col gap-1.5 px-2 pb-2">
                {issues.map((issue) => {
                  const idx = states.findIndex((s) => s.id === column.id);
                  const prev = states[idx - 1];
                  const next = states[idx + 1];
                  const pending = issue.id < 0;
                  const prio = PRIORITIES[issue.priority];
                  return (
                    <article
                      key={issue.id}
                      data-testid="issue-card"
                      data-issue-title={issue.title}
                      onClick={() => setSelectedIssueId(issue.id)}
                      className={`group cursor-pointer rounded-md border border-zinc-200 bg-white p-2 shadow-sm hover:border-indigo-300 ${
                        pending ? 'opacity-70' : ''
                      }`}
                    >
                      <div className="flex items-center gap-1.5 text-[11px] text-zinc-400">
                        <span
                          className={`inline-block h-2 w-2 rounded-full ${prio?.color ?? 'bg-zinc-300'}`}
                          title={prio?.label}
                        />
                        <span data-testid="issue-identifier">
                          {identifier(issue, team)}
                        </span>
                        {pending && <span className="text-indigo-500">保存中…</span>}
                        <span className="ml-auto hidden gap-0.5 group-hover:flex">
                          {prev && (
                            <button
                              data-testid="move-left"
                              onClick={(e) => {
                                e.stopPropagation();
                                moveTo(issue, prev);
                              }}
                              className="rounded px-1 hover:bg-zinc-100"
                            >
                              ←
                            </button>
                          )}
                          {next && (
                            <button
                              data-testid="move-right"
                              onClick={(e) => {
                                e.stopPropagation();
                                moveTo(issue, next);
                              }}
                              className="rounded px-1 hover:bg-zinc-100"
                            >
                              →
                            </button>
                          )}
                        </span>
                      </div>
                      <p className="mt-1 text-sm">{issue.title}</p>
                      <div className="mt-1 flex flex-wrap gap-1">
                        {state.issueLabels
                          .filter((il) => il.issueId === issue.id)
                          .map((il) => state.labels[il.labelId])
                          .filter((l) => l !== undefined)
                          .map((l) => (
                            <span
                              key={l.id}
                              className="rounded-full px-1.5 text-[10px] text-white"
                              style={{ backgroundColor: l.color }}
                            >
                              {l.name}
                            </span>
                          ))}
                      </div>
                    </article>
                  );
                })}
              </div>
            </section>
          );
        })}
      </main>

      {newIssueStateId !== null && (
        <NewIssueDialog
          teamId={team.id}
          stateId={newIssueStateId}
          onClose={() => setNewIssueStateId(null)}
        />
      )}
      {selectedIssueId !== null && (
        <IssueDetail
          key={selectedIssueId}
          issueId={selectedIssueId}
          onClose={() => setSelectedIssueId(null)}
        />
      )}
      <CommandPalette
        open={paletteOpen}
        team={team}
        onClose={() => setPaletteOpen(false)}
        onNewIssue={() => {
          setPaletteOpen(false);
          const backlog = states[0];
          if (backlog) setNewIssueStateId(backlog.id);
        }}
        onSelectTeam={(id) => {
          setPaletteOpen(false);
          setTeamId(id);
        }}
        onSelectIssue={(id) => {
          setPaletteOpen(false);
          setSelectedIssueId(id);
        }}
      />
    </div>
  );
}
