import type {
  Comment,
  Issue,
  Label,
  Team,
  WorkflowState,
} from '@prisma/client';
import type {
  Comment as CommentPayload,
  Issue as IssuePayload,
  Label as LabelPayload,
  Team as TeamPayload,
  WorkflowState as StatePayload,
} from '@linear/shared';

/**
 * Prisma model → client 向け payload (shared/schema/entities.ts の形)。
 * insert op の payload と bootstrap snapshot (Phase 3) はここを単一の変換点にする。
 */

export function toTeamPayload(t: Team): TeamPayload {
  return { id: t.id, workspaceId: t.workspaceId, key: t.key, name: t.name };
}

export function toStatePayload(s: WorkflowState): StatePayload {
  return {
    id: s.id,
    teamId: s.teamId,
    name: s.name,
    category: s.category,
    position: s.position,
  };
}

export function toIssuePayload(i: Issue): IssuePayload {
  return {
    id: i.id,
    teamId: i.teamId,
    number: i.number,
    title: i.title,
    description: i.description,
    stateId: i.stateId,
    priority: i.priority,
    assigneeId: i.assigneeId,
    sortOrder: i.sortOrder,
    createdById: i.createdById,
    createdAt: i.createdAt.toISOString(),
    updatedAt: i.updatedAt.toISOString(),
  };
}

export function toLabelPayload(l: Label): LabelPayload {
  return { id: l.id, teamId: l.teamId, name: l.name, color: l.color };
}

export function toCommentPayload(c: Comment): CommentPayload {
  return {
    id: c.id,
    issueId: c.issueId,
    authorId: c.authorId,
    body: c.body,
    createdAt: c.createdAt.toISOString(),
  };
}
