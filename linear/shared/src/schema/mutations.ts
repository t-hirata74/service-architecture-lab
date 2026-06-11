import { z } from 'zod';
import { MemberRoleSchema, PrioritySchema, SortOrderSchema } from './entities';

/**
 * 書き込みの唯一の入口 POST /mutations のコマンド定義 (ADR 0001/0004)。
 * backend は ZodValidationPipe で、frontend はフォーム検証と楽観適用で同じスキーマを使う。
 */

export const CreateTeamCommandSchema = z.object({
  type: z.literal('createTeam'),
  key: z
    .string()
    .regex(/^[A-Z][A-Z0-9]{0,9}$/, 'team key is 1-10 uppercase chars (e.g. ENG)'),
  name: z.string().min(1).max(100),
});

export const CreateIssueCommandSchema = z.object({
  type: z.literal('createIssue'),
  teamId: z.number().int(),
  title: z.string().min(1).max(255),
  description: z.string().max(10_000).optional(),
  stateId: z.number().int().optional(),
  priority: PrioritySchema.optional(),
  assigneeId: z.number().int().nullable().optional(),
  labelIds: z.array(z.number().int()).max(20).optional(),
  sortOrder: SortOrderSchema.optional(),
});

export const IssuePatchSchema = z
  .object({
    title: z.string().min(1).max(255).optional(),
    description: z.string().max(10_000).nullable().optional(),
    priority: PrioritySchema.optional(),
    assigneeId: z.number().int().nullable().optional(),
    stateId: z.number().int().optional(),
  })
  .refine((p) => Object.keys(p).length > 0, 'patch must not be empty');

export const UpdateIssueCommandSchema = z.object({
  type: z.literal('updateIssue'),
  issueId: z.number().int(),
  patch: IssuePatchSchema,
});

export const MoveIssueCommandSchema = z.object({
  type: z.literal('moveIssue'),
  issueId: z.number().int(),
  stateId: z.number().int(),
  sortOrder: SortOrderSchema,
});

export const DeleteIssueCommandSchema = z.object({
  type: z.literal('deleteIssue'),
  issueId: z.number().int(),
});

export const CreateCommentCommandSchema = z.object({
  type: z.literal('createComment'),
  issueId: z.number().int(),
  body: z.string().min(1).max(10_000),
});

export const CreateLabelCommandSchema = z.object({
  type: z.literal('createLabel'),
  teamId: z.number().int(),
  name: z.string().min(1).max(50),
  color: z.string().regex(/^#[0-9a-fA-F]{6}$/),
});

export const AddIssueLabelCommandSchema = z.object({
  type: z.literal('addIssueLabel'),
  issueId: z.number().int(),
  labelId: z.number().int(),
});

export const RemoveIssueLabelCommandSchema = z.object({
  type: z.literal('removeIssueLabel'),
  issueId: z.number().int(),
  labelId: z.number().int(),
});

/**
 * 登録済みユーザの email を指定して直接 member に加える (ADR 0006)。
 * 対象 userId は server が解決するため、このコマンドは楽観適用されない
 * (reducer.applyCommand は no-op、確定 op で反映)。admin 限定。
 */
export const InviteMemberCommandSchema = z.object({
  type: z.literal('inviteMember'),
  email: z.string().email().max(255),
  role: MemberRoleSchema,
});

/** admin 限定。自分自身は remove できない */
export const RemoveMemberCommandSchema = z.object({
  type: z.literal('removeMember'),
  userId: z.number().int().positive(),
});

export const MutationCommandSchema = z.discriminatedUnion('type', [
  InviteMemberCommandSchema,
  RemoveMemberCommandSchema,
  CreateTeamCommandSchema,
  CreateIssueCommandSchema,
  UpdateIssueCommandSchema,
  MoveIssueCommandSchema,
  DeleteIssueCommandSchema,
  CreateCommentCommandSchema,
  CreateLabelCommandSchema,
  AddIssueLabelCommandSchema,
  RemoveIssueLabelCommandSchema,
]);
export type MutationCommand = z.infer<typeof MutationCommandSchema>;

/** clientMutationId は client 採番の UUID。再送の冪等 key になる (ADR 0002/0003)。 */
export const MutationRequestSchema = z.object({
  clientMutationId: z.string().uuid(),
  workspaceId: z.number().int(),
  command: MutationCommandSchema,
});
export type MutationRequest = z.infer<typeof MutationRequestSchema>;
