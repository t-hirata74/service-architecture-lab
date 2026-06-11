import { z } from 'zod';

/** query string は文字列で届くため coerce する (backend 専用スキーマ) */
export const BootstrapQuerySchema = z.object({
  workspaceId: z.coerce.number().int().positive(),
});
export type BootstrapQuery = z.infer<typeof BootstrapQuerySchema>;

export const DeltaQuerySchema = z.object({
  workspaceId: z.coerce.number().int().positive(),
  since: z.coerce.number().int().min(0),
});
export type DeltaQuery = z.infer<typeof DeltaQuerySchema>;

export const ActivityQuerySchema = z.object({
  workspaceId: z.coerce.number().int().positive(),
  issueId: z.coerce.number().int().positive(),
});
export type ActivityQuery = z.infer<typeof ActivityQuerySchema>;
