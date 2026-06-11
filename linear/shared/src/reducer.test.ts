import { describe, expect, it } from 'vitest';
import {
  applyCommand,
  applyOp,
  emptySnapshot,
  fromBootstrap,
  tempIdCount,
  WorkspaceSnapshot,
} from './reducer';
import type { Issue, SyncOp } from './index';

const issue = (over: Partial<Issue> = {}): Issue => ({
  id: 10,
  teamId: 1,
  number: 1,
  title: 'Issue',
  description: null,
  stateId: 100,
  priority: 0,
  assigneeId: null,
  sortOrder: 'V',
  createdById: 1,
  createdAt: '2026-06-10T00:00:00.000Z',
  updatedAt: '2026-06-10T00:00:00.000Z',
  ...over,
});

const op = (over: Partial<SyncOp>): SyncOp => ({
  seq: 1,
  workspaceId: 1,
  entityType: 'issue',
  entityId: 10,
  action: 'insert',
  payload: {},
  actorId: 1,
  clientMutationId: null,
  ...over,
});

function baseSnapshot(): WorkspaceSnapshot {
  return fromBootstrap({
    workspace: { id: 1, name: 'WS', urlKey: 'ws-1' },
    users: [{ id: 1, name: 'Alice' }],
    members: [{ workspaceId: 1, userId: 1, role: 'admin' }],
    teams: [{ id: 1, workspaceId: 1, key: 'GEN', name: 'General' }],
    states: [
      { id: 100, teamId: 1, name: 'Backlog', category: 'backlog', position: 0 },
      { id: 101, teamId: 1, name: 'Todo', category: 'unstarted', position: 1 },
    ],
    issues: [issue()],
    labels: [{ id: 5, teamId: 1, name: 'bug', color: '#ff0000' }],
    issueLabels: [{ issueId: 10, labelId: 5 }],
    comments: [
      {
        id: 7,
        issueId: 10,
        authorId: 1,
        body: 'hi',
        createdAt: '2026-06-10T00:00:00.000Z',
      },
    ],
    lastSyncId: 0,
  });
}

describe('applyOp', () => {
  it('insert → update の merge が効く', () => {
    let snap = emptySnapshot();
    snap = applyOp(snap, op({ payload: issue() as unknown as Record<string, unknown> }));
    snap = applyOp(
      snap,
      op({ seq: 2, action: 'update', payload: { title: 'Renamed', priority: 2 } }),
    );
    expect(snap.issues[10]).toMatchObject({ title: 'Renamed', priority: 2, number: 1 });
  });

  it('存在しない entity への update は無視する (堅牢性)', () => {
    const snap = applyOp(emptySnapshot(), op({ action: 'update', payload: { title: 'x' } }));
    expect(snap.issues[10]).toBeUndefined();
  });

  it('issue delete は comments / issueLabels をカスケードで落とす', () => {
    const snap = applyOp(baseSnapshot(), op({ action: 'delete', payload: { id: 10 } }));
    expect(snap.issues[10]).toBeUndefined();
    expect(Object.keys(snap.comments)).toHaveLength(0);
    expect(snap.issueLabels).toHaveLength(0);
    expect(snap.labels[5]).toBeDefined(); // label 本体は残る
  });

  it('issue_label の insert は重複しない / delete はペアを除く', () => {
    let snap = baseSnapshot();
    snap = applyOp(
      snap,
      op({ entityType: 'issue_label', payload: { issueId: 10, labelId: 5 } }),
    );
    expect(snap.issueLabels).toHaveLength(1);
    snap = applyOp(
      snap,
      op({
        entityType: 'issue_label',
        action: 'delete',
        payload: { issueId: 10, labelId: 5 },
      }),
    );
    expect(snap.issueLabels).toHaveLength(0);
  });

  it('元の snapshot を変更しない (純関数)', () => {
    const before = baseSnapshot();
    const json = JSON.stringify(before);
    applyOp(before, op({ action: 'delete', payload: { id: 10 } }));
    expect(JSON.stringify(before)).toBe(json);
  });
});

describe('applyOp: workspace_member (E1 / ADR 0006)', () => {
  it('insert は members と users の両方へ反映される', () => {
    const snap = applyOp(
      baseSnapshot(),
      op({
        entityType: 'workspace_member',
        entityId: 2,
        payload: {
          workspaceId: 1,
          userId: 2,
          role: 'member',
          user: { id: 2, name: 'Bob' },
        },
      }),
    );
    expect(snap.members).toHaveLength(2);
    expect(snap.users[2]).toEqual({ id: 2, name: 'Bob' });
  });

  it('delete は member と users (membership 従属) を落とす', () => {
    let snap = applyOp(
      baseSnapshot(),
      op({
        entityType: 'workspace_member',
        entityId: 2,
        payload: {
          workspaceId: 1,
          userId: 2,
          role: 'member',
          user: { id: 2, name: 'Bob' },
        },
      }),
    );
    snap = applyOp(
      snap,
      op({
        seq: 2,
        entityType: 'workspace_member',
        entityId: 2,
        action: 'delete',
        payload: { userId: 2 },
      }),
    );
    expect(snap.members).toHaveLength(1);
    expect(snap.users[2]).toBeUndefined();
  });
});

describe('applyCommand (optimistic)', () => {
  const ctx = (tempIds: number[]) => ({
    actorId: 1,
    tempIds,
    nowIso: '2026-06-10T12:00:00.000Z',
  });

  it('createIssue: temp id で挿入され、既定 state / 末尾 sortOrder になる', () => {
    const snap = applyCommand(
      baseSnapshot(),
      { type: 'createIssue', teamId: 1, title: 'Optimistic' },
      ctx([-1]),
    );
    const created = snap.issues[-1]!;
    expect(created).toMatchObject({
      id: -1,
      stateId: 100, // Backlog (position 0)
      number: 0,
      createdById: 1,
    });
    expect(created.sortOrder > 'V').toBe(true); // 既存 'V' の後ろ
  });

  it('createTeam: team + 既定 5 states が temp id で入る (tempIdCount=6)', () => {
    const cmd = { type: 'createTeam', key: 'ENG', name: 'Eng' } as const;
    expect(tempIdCount(cmd)).toBe(6);
    const snap = applyCommand(baseSnapshot(), cmd, ctx([-1, -2, -3, -4, -5, -6]));
    expect(snap.teams[-1]).toMatchObject({ key: 'ENG' });
    expect(
      Object.values(snap.states).filter((s) => s.teamId === -1),
    ).toHaveLength(5);
  });

  it('createComment: 対象 issue が無ければ no-op', () => {
    const snap = applyCommand(
      baseSnapshot(),
      { type: 'createComment', issueId: 999, body: 'orphan' },
      ctx([-1]),
    );
    expect(Object.keys(snap.comments)).toHaveLength(1);
  });

  it('inviteMember は楽観適用されない (server-resolved) / removeMember は楽観で消える', () => {
    const base = baseSnapshot();
    const invited = applyCommand(
      base,
      { type: 'inviteMember', email: 'bob@example.com', role: 'member' },
      ctx([]),
    );
    expect(invited.members).toHaveLength(1); // no-op

    const removed = applyCommand(
      base,
      { type: 'removeMember', userId: 1 },
      ctx([]),
    );
    expect(removed.members).toHaveLength(0);
    expect(removed.users[1]).toBeUndefined();
  });

  it('再導出が決定的 (同じ ctx なら同じ結果)', () => {
    const cmd = {
      type: 'createIssue',
      teamId: 1,
      title: 'Det',
      sortOrder: 'X',
    } as const;
    const a = applyCommand(baseSnapshot(), cmd, ctx([-7]));
    const b = applyCommand(baseSnapshot(), cmd, ctx([-7]));
    expect(a).toEqual(b);
  });
});
