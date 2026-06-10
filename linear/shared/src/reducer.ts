import { DEFAULT_WORKFLOW_STATES } from './default-states';
import { keyBetween } from './fractional';
import type {
  Comment,
  Issue,
  IssueLabel,
  Label,
  Team,
  UserPublic,
  WorkflowState,
  Workspace,
  WorkspaceMember,
} from './schema/entities';
import type { MutationCommand } from './schema/mutations';
import type { BootstrapResponse, SyncOp } from './schema/sync';

/**
 * client 側の materialized state と、それに対する 2 つの適用関数 (ADR 0003/0004)。
 *
 * - applyOp:      server 確定 op の適用。backend の DB 適用と意味的に等価であること
 *                 (backend test/reducer-parity.e2e-spec.ts で突き合わせる)
 * - applyCommand: 未確定 mutation の楽観適用。display = confirmed に pending を
 *                 順に applyCommand した導出値 (rebase 方式)
 *
 * どちらも純関数で、元の snapshot を変更しない (shallow copy)。
 */

export interface WorkspaceSnapshot {
  workspace: Workspace | null;
  users: Record<number, UserPublic>;
  members: WorkspaceMember[];
  teams: Record<number, Team>;
  states: Record<number, WorkflowState>;
  issues: Record<number, Issue>;
  labels: Record<number, Label>;
  issueLabels: IssueLabel[];
  comments: Record<number, Comment>;
}

export function emptySnapshot(): WorkspaceSnapshot {
  return {
    workspace: null,
    users: {},
    members: [],
    teams: {},
    states: {},
    issues: {},
    labels: {},
    issueLabels: [],
    comments: {},
  };
}

export function fromBootstrap(b: BootstrapResponse): WorkspaceSnapshot {
  return {
    workspace: b.workspace,
    users: indexBy(b.users),
    members: [...b.members],
    teams: indexBy(b.teams),
    states: indexBy(b.states),
    issues: indexBy(b.issues),
    labels: indexBy(b.labels),
    issueLabels: [...b.issueLabels],
    comments: indexBy(b.comments),
  };
}

function indexBy<T extends { id: number }>(items: T[]): Record<number, T> {
  const out: Record<number, T> = {};
  for (const item of items) out[item.id] = item;
  return out;
}

// ─── server 確定 op の適用 ──────────────────────────────────────────────────

export function applyOp(snap: WorkspaceSnapshot, op: SyncOp): WorkspaceSnapshot {
  switch (op.entityType) {
    case 'team':
      return applyEntityOp(snap, op, 'teams', deleteTeamCascade);
    case 'workflow_state':
      return applyEntityOp(snap, op, 'states', null);
    case 'issue':
      return applyEntityOp(snap, op, 'issues', deleteIssueCascade);
    case 'label':
      return applyEntityOp(snap, op, 'labels', deleteLabelCascade);
    case 'comment':
      return applyEntityOp(snap, op, 'comments', null);
    case 'issue_label': {
      const pair = op.payload as unknown as IssueLabel;
      if (op.action === 'insert') {
        if (hasPair(snap.issueLabels, pair)) return snap;
        return { ...snap, issueLabels: [...snap.issueLabels, pair] };
      }
      if (op.action === 'delete') {
        return {
          ...snap,
          issueLabels: snap.issueLabels.filter(
            (il) => !(il.issueId === pair.issueId && il.labelId === pair.labelId),
          ),
        };
      }
      return snap;
    }
  }
}

type EntityKey = 'teams' | 'states' | 'issues' | 'labels' | 'comments';

function applyEntityOp(
  snap: WorkspaceSnapshot,
  op: SyncOp,
  key: EntityKey,
  deleteCascade:
    | ((snap: WorkspaceSnapshot, id: number) => WorkspaceSnapshot)
    | null,
): WorkspaceSnapshot {
  const table = snap[key] as Record<number, Record<string, unknown>>;
  switch (op.action) {
    case 'insert': {
      const entity = op.payload as Record<string, unknown>;
      return { ...snap, [key]: { ...table, [op.entityId]: entity } };
    }
    case 'update': {
      const existing = table[op.entityId];
      // catch-up は insert が先に来る順序保証があるため、欠けていたら黙って無視する
      if (!existing) return snap;
      const merged = { ...existing, ...(op.payload as Record<string, unknown>) };
      return { ...snap, [key]: { ...table, [op.entityId]: merged } };
    }
    case 'delete': {
      if (deleteCascade) return deleteCascade(snap, op.entityId);
      const next = { ...table };
      delete next[op.entityId];
      return { ...snap, [key]: next };
    }
  }
}

/** issue delete は配下の comments / issue_labels も併せて落とす規約 (issues.service と対) */
function deleteIssueCascade(
  snap: WorkspaceSnapshot,
  issueId: number,
): WorkspaceSnapshot {
  const issues = { ...snap.issues };
  delete issues[issueId];
  const comments: Record<number, Comment> = {};
  for (const c of Object.values(snap.comments)) {
    if (c.issueId !== issueId) comments[c.id] = c;
  }
  return {
    ...snap,
    issues,
    comments,
    issueLabels: snap.issueLabels.filter((il) => il.issueId !== issueId),
  };
}

function deleteLabelCascade(
  snap: WorkspaceSnapshot,
  labelId: number,
): WorkspaceSnapshot {
  const labels = { ...snap.labels };
  delete labels[labelId];
  return {
    ...snap,
    labels,
    issueLabels: snap.issueLabels.filter((il) => il.labelId !== labelId),
  };
}

function deleteTeamCascade(
  snap: WorkspaceSnapshot,
  teamId: number,
): WorkspaceSnapshot {
  let next = snap;
  for (const issue of Object.values(snap.issues)) {
    if (issue.teamId === teamId) next = deleteIssueCascade(next, issue.id);
  }
  const teams = { ...next.teams };
  delete teams[teamId];
  const states: Record<number, WorkflowState> = {};
  for (const s of Object.values(next.states)) {
    if (s.teamId !== teamId) states[s.id] = s;
  }
  const labels: Record<number, Label> = {};
  for (const l of Object.values(next.labels)) {
    if (l.teamId !== teamId) labels[l.id] = l;
  }
  return { ...next, teams, states, labels };
}

function hasPair(list: IssueLabel[], pair: IssueLabel): boolean {
  return list.some(
    (il) => il.issueId === pair.issueId && il.labelId === pair.labelId,
  );
}

// ─── 未確定 mutation の楽観適用 ─────────────────────────────────────────────

export interface CommandContext {
  actorId: number;
  /** mutate() 時に固定割当てされた一時 id (負数)。再導出でも同じ値が使われる */
  tempIds: number[];
  /** mutate() 時に固定された ISO timestamp。再導出で揺れないようにする */
  nowIso: string;
}

/** command が必要とする一時 id の個数 (SyncEngine の割当てと位置対応) */
export function tempIdCount(command: MutationCommand): number {
  switch (command.type) {
    case 'createTeam':
      return 1 + DEFAULT_WORKFLOW_STATES.length;
    case 'createIssue':
    case 'createComment':
    case 'createLabel':
      return 1;
    default:
      return 0;
  }
}

export function applyCommand(
  snap: WorkspaceSnapshot,
  command: MutationCommand,
  ctx: CommandContext,
): WorkspaceSnapshot {
  let cursor = 0;
  const take = (): number => {
    const v = ctx.tempIds[cursor];
    cursor += 1;
    if (v === undefined) throw new Error('tempIds exhausted');
    return v;
  };

  switch (command.type) {
    case 'createTeam': {
      const teamId = take();
      const team: Team = {
        id: teamId,
        workspaceId: snap.workspace?.id ?? 0,
        key: command.key,
        name: command.name,
      };
      const states = { ...snap.states };
      DEFAULT_WORKFLOW_STATES.forEach((s, i) => {
        const id = take();
        states[id] = { id, teamId, name: s.name, category: s.category, position: i };
      });
      return { ...snap, teams: { ...snap.teams, [teamId]: team }, states };
    }
    case 'createIssue': {
      const id = take();
      const stateId = command.stateId ?? defaultStateId(snap, command.teamId);
      const issue: Issue = {
        id,
        teamId: command.teamId,
        number: 0, // server 採番までのプレースホルダ (UI は draft 表示)
        title: command.title,
        description: command.description ?? null,
        stateId,
        priority: command.priority ?? 0,
        assigneeId: command.assigneeId ?? null,
        sortOrder:
          command.sortOrder ?? appendOrderKey(snap, command.teamId, stateId),
        createdById: ctx.actorId,
        createdAt: ctx.nowIso,
        updatedAt: ctx.nowIso,
      };
      let issueLabels = snap.issueLabels;
      for (const labelId of command.labelIds ?? []) {
        issueLabels = [...issueLabels, { issueId: id, labelId }];
      }
      return { ...snap, issues: { ...snap.issues, [id]: issue }, issueLabels };
    }
    case 'updateIssue': {
      const existing = snap.issues[command.issueId];
      if (!existing) return snap;
      const updated: Issue = { ...existing, updatedAt: ctx.nowIso };
      if (command.patch.title !== undefined) updated.title = command.patch.title;
      if (command.patch.description !== undefined)
        updated.description = command.patch.description;
      if (command.patch.priority !== undefined)
        updated.priority = command.patch.priority;
      if (command.patch.assigneeId !== undefined)
        updated.assigneeId = command.patch.assigneeId;
      if (command.patch.stateId !== undefined)
        updated.stateId = command.patch.stateId;
      return { ...snap, issues: { ...snap.issues, [command.issueId]: updated } };
    }
    case 'moveIssue': {
      const existing = snap.issues[command.issueId];
      if (!existing) return snap;
      const updated: Issue = {
        ...existing,
        stateId: command.stateId,
        sortOrder: command.sortOrder,
        updatedAt: ctx.nowIso,
      };
      return { ...snap, issues: { ...snap.issues, [command.issueId]: updated } };
    }
    case 'deleteIssue':
      return snap.issues[command.issueId]
        ? deleteIssueCascade(snap, command.issueId)
        : snap;
    case 'createComment': {
      if (!snap.issues[command.issueId]) return snap;
      const id = take();
      const comment: Comment = {
        id,
        issueId: command.issueId,
        authorId: ctx.actorId,
        body: command.body,
        createdAt: ctx.nowIso,
      };
      return { ...snap, comments: { ...snap.comments, [id]: comment } };
    }
    case 'createLabel': {
      const id = take();
      const label: Label = {
        id,
        teamId: command.teamId,
        name: command.name,
        color: command.color,
      };
      return { ...snap, labels: { ...snap.labels, [id]: label } };
    }
    case 'addIssueLabel': {
      const pair = { issueId: command.issueId, labelId: command.labelId };
      if (hasPair(snap.issueLabels, pair)) return snap;
      return { ...snap, issueLabels: [...snap.issueLabels, pair] };
    }
    case 'removeIssueLabel':
      return {
        ...snap,
        issueLabels: snap.issueLabels.filter(
          (il) =>
            !(il.issueId === command.issueId && il.labelId === command.labelId),
        ),
      };
  }
}

/** team の先頭 state (position 順)。server の createIssue デフォルトと同じ規則 */
export function defaultStateId(snap: WorkspaceSnapshot, teamId: number): number {
  const states = Object.values(snap.states)
    .filter((s) => s.teamId === teamId)
    .sort((a, b) => a.position - b.position || a.id - b.id);
  const first = states[0];
  if (!first) throw new Error(`team ${teamId} has no workflow states`);
  return first.id;
}

/** 列末尾に追加する order key。server issues.service の appendOrderKey と同じ規則 */
export function appendOrderKey(
  snap: WorkspaceSnapshot,
  teamId: number,
  stateId: number,
): string {
  let max: string | null = null;
  for (const issue of Object.values(snap.issues)) {
    if (issue.teamId !== teamId || issue.stateId !== stateId) continue;
    if (max === null || issue.sortOrder > max) max = issue.sortOrder;
  }
  return keyBetween(max, null);
}
