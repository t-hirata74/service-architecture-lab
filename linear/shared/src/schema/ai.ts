import { z } from 'zod';
import { PrioritySchema } from './entities';

/** backend `POST /ai/triage` (→ ai-worker 内部 ingress) のコントラクト */
export const TriageRequestSchema = z.object({
  workspaceId: z.number().int().positive(),
  issueId: z.number().int().positive(),
});
export type TriageRequest = z.infer<typeof TriageRequestSchema>;

/**
 * ai-worker 停止時は available=false / suggestion=null で degrade する
 * (本流の issue 操作は止めない)。
 */
export const TriageResponseSchema = z.object({
  available: z.boolean(),
  suggestion: z
    .object({
      priority: PrioritySchema,
      labels: z.array(z.string()),
      reason: z.string(),
      duplicateIssueIds: z.array(z.number().int()),
    })
    .nullable(),
});
export type TriageResponse = z.infer<typeof TriageResponseSchema>;
