import { z } from 'zod';

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
