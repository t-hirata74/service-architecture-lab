import { z } from 'zod';

/**
 * client から見た entity の形 (sync op payload / bootstrap snapshot の単位)。
 * 日付は ISO8601 文字列、id は数値。backend の serializer がこの形に揃える。
 */

export const MemberRoleSchema = z.enum(['admin', 'member']);
export type MemberRole = z.infer<typeof MemberRoleSchema>;

export const StateCategorySchema = z.enum([
  'backlog',
  'unstarted',
  'started',
  'completed',
  'canceled',
]);
export type StateCategory = z.infer<typeof StateCategorySchema>;

/** 0=none / 1=urgent / 2=high / 3=medium / 4=low (Linear 準拠の並び) */
export const PrioritySchema = z.number().int().min(0).max(4);

export const SortOrderSchema = z
  .string()
  .min(1)
  .max(64)
  .regex(/^[0-9A-Za-z]*[1-9A-Za-z]$/, 'order key must not end with "0"');

export const UserPublicSchema = z.object({
  id: z.number().int(),
  name: z.string(),
});
export type UserPublic = z.infer<typeof UserPublicSchema>;

export const WorkspaceSchema = z.object({
  id: z.number().int(),
  name: z.string(),
  urlKey: z.string(),
});
export type Workspace = z.infer<typeof WorkspaceSchema>;

export const WorkspaceMemberSchema = z.object({
  workspaceId: z.number().int(),
  userId: z.number().int(),
  role: MemberRoleSchema,
});
export type WorkspaceMember = z.infer<typeof WorkspaceMemberSchema>;

export const TeamSchema = z.object({
  id: z.number().int(),
  workspaceId: z.number().int(),
  key: z.string(),
  name: z.string(),
});
export type Team = z.infer<typeof TeamSchema>;

export const WorkflowStateSchema = z.object({
  id: z.number().int(),
  teamId: z.number().int(),
  name: z.string(),
  category: StateCategorySchema,
  position: z.number().int(),
});
export type WorkflowState = z.infer<typeof WorkflowStateSchema>;

export const IssueSchema = z.object({
  id: z.number().int(),
  teamId: z.number().int(),
  number: z.number().int(),
  title: z.string(),
  description: z.string().nullable(),
  stateId: z.number().int(),
  priority: PrioritySchema,
  assigneeId: z.number().int().nullable(),
  sortOrder: SortOrderSchema,
  createdById: z.number().int(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type Issue = z.infer<typeof IssueSchema>;

export const LabelSchema = z.object({
  id: z.number().int(),
  teamId: z.number().int(),
  name: z.string(),
  color: z.string(),
});
export type Label = z.infer<typeof LabelSchema>;

export const IssueLabelSchema = z.object({
  issueId: z.number().int(),
  labelId: z.number().int(),
});
export type IssueLabel = z.infer<typeof IssueLabelSchema>;

export const CommentSchema = z.object({
  id: z.number().int(),
  issueId: z.number().int(),
  authorId: z.number().int(),
  body: z.string(),
  createdAt: z.string(),
});
export type Comment = z.infer<typeof CommentSchema>;
