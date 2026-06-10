import { StateCategory } from '@prisma/client';

/** team 作成時に seed する既定の workflow states (position = 配列順) */
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
