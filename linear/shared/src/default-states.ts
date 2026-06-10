import type { StateCategory } from './schema/entities';

/**
 * team 作成時に seed される既定の workflow states (position = 配列順)。
 * backend (teams.service / auth.service) と client の optimistic 適用
 * (reducer.applyCommand) の両方がここを single source にする (ADR 0004)。
 */
export const DEFAULT_WORKFLOW_STATES: ReadonlyArray<{
  name: string;
  category: StateCategory;
}> = [
  { name: 'Backlog', category: 'backlog' },
  { name: 'Todo', category: 'unstarted' },
  { name: 'In Progress', category: 'started' },
  { name: 'Done', category: 'completed' },
  { name: 'Canceled', category: 'canceled' },
];
