import { z } from 'zod';
import {
  CommentSchema,
  IssueLabelSchema,
  IssueSchema,
  LabelSchema,
  TeamSchema,
  UserPublicSchema,
  WorkflowStateSchema,
  WorkspaceMemberSchema,
  WorkspaceSchema,
} from './entities';

/**
 * sync protocol (ADR 0002)。
 * op は server 採番 seq で全順序。client は lastSyncId の連続性だけを信じる。
 */

export const EntityTypeSchema = z.enum([
  'team',
  'workflow_state',
  'issue',
  'label',
  'issue_label',
  'comment',
]);
export type EntityType = z.infer<typeof EntityTypeSchema>;

export const OpActionSchema = z.enum(['insert', 'update', 'delete']);
export type OpAction = z.infer<typeof OpActionSchema>;

/**
 * payload の形:
 * - insert: entity 全体 (entities.ts のスキーマ)
 * - update: 変更フィールドのみの partial (+ updatedAt)
 * - delete: { id } (issue_label は { issueId, labelId })
 * issue_label は複合キーのため entityId = issueId とし、payload に両方を持つ。
 */
export const SyncOpSchema = z.object({
  seq: z.number().int().positive(),
  workspaceId: z.number().int(),
  entityType: EntityTypeSchema,
  entityId: z.number().int(),
  action: OpActionSchema,
  payload: z.record(z.unknown()),
  actorId: z.number().int(),
  clientMutationId: z.string().uuid().nullable(),
});
export type SyncOp = z.infer<typeof SyncOpSchema>;

export const MutationResponseSchema = z.object({
  ops: z.array(SyncOpSchema),
  lastSyncId: z.number().int(),
});
export type MutationResponse = z.infer<typeof MutationResponseSchema>;

/**
 * bootstrap: materialized 現在状態の全量 snapshot + その時点の lastSyncId。
 * snapshot と lastSyncId は server 側で同一トランザクションから読まれており、
 * `delta(since=lastSyncId)` を続ければ漏れなく追いつける (ADR 0002)。
 */
export const BootstrapResponseSchema = z.object({
  workspace: WorkspaceSchema,
  users: z.array(UserPublicSchema),
  members: z.array(WorkspaceMemberSchema),
  teams: z.array(TeamSchema),
  states: z.array(WorkflowStateSchema),
  issues: z.array(IssueSchema),
  labels: z.array(LabelSchema),
  issueLabels: z.array(IssueLabelSchema),
  comments: z.array(CommentSchema),
  lastSyncId: z.number().int().min(0),
});
export type BootstrapResponse = z.infer<typeof BootstrapResponseSchema>;

export const DeltaResponseSchema = z.object({
  ops: z.array(SyncOpSchema),
  lastSyncId: z.number().int().min(0),
});
export type DeltaResponse = z.infer<typeof DeltaResponseSchema>;

/**
 * WS (server → client) メッセージ (ADR 0005)。
 * - hello: 接続直後に現在の lastSyncId を通知。client はここから delta で catch-up する
 * - op: 確定 op の push。連続性 (seq = lastSyncId + 1) が崩れていたら delta で自己修復
 */
export const ServerWsMessageSchema = z.discriminatedUnion('type', [
  z.object({
    type: z.literal('hello'),
    workspaceId: z.number().int(),
    lastSyncId: z.number().int().min(0),
  }),
  z.object({ type: z.literal('op'), op: SyncOpSchema }),
]);
export type ServerWsMessage = z.infer<typeof ServerWsMessageSchema>;

/** WS close code (4000 番台 = アプリ定義) */
export const WS_CLOSE_INVALID_PARAMS = 4400;
export const WS_CLOSE_UNAUTHORIZED = 4401;
export const WS_CLOSE_FORBIDDEN = 4403;
