import type { Issue, Team, WorkspaceSnapshot } from '@linear/shared';

export const PRIORITIES: ReadonlyArray<{ value: number; label: string; color: string }> = [
  { value: 0, label: 'None', color: 'bg-zinc-300' },
  { value: 1, label: 'Urgent', color: 'bg-red-500' },
  { value: 2, label: 'High', color: 'bg-orange-500' },
  { value: 3, label: 'Medium', color: 'bg-yellow-500' },
  { value: 4, label: 'Low', color: 'bg-zinc-400' },
];

/** GEN-42 / 未確定 (楽観中) は GEN-… */
export function identifier(issue: Issue, team: Team | undefined): string {
  const key = team?.key ?? '?';
  return issue.number > 0 ? `${key}-${issue.number}` : `${key}-…`;
}

export function issuesInColumn(
  snap: WorkspaceSnapshot,
  teamId: number,
  stateId: number,
): Issue[] {
  return Object.values(snap.issues)
    .filter((i) => i.teamId === teamId && i.stateId === stateId)
    .sort((a, b) =>
      a.sortOrder < b.sortOrder ? -1 : a.sortOrder > b.sortOrder ? 1 : 0,
    );
}
