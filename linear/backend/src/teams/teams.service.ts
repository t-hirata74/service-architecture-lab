import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { z } from 'zod';
import type {
  CreateLabelCommandSchema,
  CreateTeamCommandSchema,
} from '@linear/shared';
import { Prisma } from '@prisma/client';
import { OpDraft } from '../sync/sync.service';
import {
  toLabelPayload,
  toStatePayload,
  toTeamPayload,
} from '../sync/payloads';
import { DEFAULT_WORKFLOW_STATES } from './default-states';

type Tx = Prisma.TransactionClient;
type CreateTeamCommand = z.infer<typeof CreateTeamCommandSchema>;
type CreateLabelCommand = z.infer<typeof CreateLabelCommandSchema>;

@Injectable()
export class TeamsService {
  /** team 作成は既定 workflow states の seed も含めて 1 mutation = N ops になる */
  async createTeam(
    tx: Tx,
    workspaceId: number,
    cmd: CreateTeamCommand,
  ): Promise<OpDraft[]> {
    const dup = await tx.team.findUnique({
      where: { workspaceId_key: { workspaceId, key: cmd.key } },
    });
    if (dup) throw new ConflictException(`team key "${cmd.key}" already used`);

    const team = await tx.team.create({
      data: { workspaceId, key: cmd.key, name: cmd.name },
    });
    const drafts: OpDraft[] = [
      {
        entityType: 'team',
        entityId: team.id,
        action: 'insert',
        payload: toTeamPayload(team),
      },
    ];
    for (const [i, s] of DEFAULT_WORKFLOW_STATES.entries()) {
      const state = await tx.workflowState.create({
        data: {
          teamId: team.id,
          name: s.name,
          category: s.category,
          position: i,
        },
      });
      drafts.push({
        entityType: 'workflow_state',
        entityId: state.id,
        action: 'insert',
        payload: toStatePayload(state),
      });
    }
    return drafts;
  }

  async createLabel(
    tx: Tx,
    workspaceId: number,
    cmd: CreateLabelCommand,
  ): Promise<OpDraft[]> {
    const team = await tx.team.findFirst({
      where: { id: cmd.teamId, workspaceId },
    });
    if (!team) {
      throw new NotFoundException('team not found in workspace');
    }
    const dup = await tx.label.findUnique({
      where: { teamId_name: { teamId: team.id, name: cmd.name } },
    });
    if (dup) throw new ConflictException(`label "${cmd.name}" already exists`);

    const label = await tx.label.create({
      data: { teamId: team.id, name: cmd.name, color: cmd.color },
    });
    return [
      {
        entityType: 'label',
        entityId: label.id,
        action: 'insert',
        payload: toLabelPayload(label),
      },
    ];
  }
}
