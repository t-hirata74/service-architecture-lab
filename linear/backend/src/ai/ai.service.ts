import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import type { TriageRequest, TriageResponse } from '@linear/shared';
import { z } from 'zod';
import { PrismaService } from '../prisma/prisma.service';
import { WorkspacesService } from '../workspaces/workspaces.service';

/** ai-worker のレスポンス契約 (worker 側 pydantic と対) */
const WorkerTriageSchema = z.object({
  priority: z.number().int().min(0).max(4),
  labels: z.array(z.string()),
  reason: z.string(),
});

const WorkerDuplicatesSchema = z.object({
  duplicate_ids: z.array(z.number().int()),
});

/**
 * backend → ai-worker の内部 ingress (他プロジェクトと同形: 共有トークン + 同期 REST)。
 * ai-worker 停止・タイムアウトは available=false へ degrade し、本流を止めない
 * (uber の ETA graceful degradation と同方針)。
 */
@Injectable()
export class AiService {
  private readonly logger = new Logger(AiService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly workspaces: WorkspacesService,
  ) {}

  async triage(userId: number, req: TriageRequest): Promise<TriageResponse> {
    await this.workspaces.assertMember(req.workspaceId, userId);
    const issue = await this.prisma.issue.findFirst({
      where: { id: req.issueId, team: { workspaceId: req.workspaceId } },
    });
    if (!issue) throw new NotFoundException('issue not found in workspace');

    const candidates = await this.prisma.issue.findMany({
      where: { teamId: issue.teamId, id: { not: issue.id } },
      select: { id: true, title: true },
      orderBy: { id: 'desc' },
      take: 50,
    });

    try {
      const [triage, duplicates] = await Promise.all([
        this.post('/triage', {
          title: issue.title,
          description: issue.description ?? '',
        }).then((j) => WorkerTriageSchema.parse(j)),
        this.post('/duplicates', { title: issue.title, candidates }).then((j) =>
          WorkerDuplicatesSchema.parse(j),
        ),
      ]);
      return {
        available: true,
        suggestion: {
          priority: triage.priority,
          labels: triage.labels,
          reason: triage.reason,
          duplicateIssueIds: duplicates.duplicate_ids,
        },
      };
    } catch (e) {
      this.logger.warn(`ai-worker unavailable: ${String(e)}`);
      return { available: false, suggestion: null };
    }
  }

  private async post(path: string, body: unknown): Promise<unknown> {
    // テストで差し替えられるよう call 時に env を読む (ConfigService の snapshot を避ける)
    const base = process.env.AI_WORKER_URL ?? 'http://localhost:8130';
    const token = process.env.AI_INTERNAL_TOKEN ?? 'dev-internal-token';
    const res = await fetch(`${base}${path}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Internal-Token': token,
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(1_500),
    });
    if (!res.ok) throw new Error(`ai-worker responded ${res.status}`);
    return res.json();
  }
}
