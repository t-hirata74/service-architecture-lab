import {
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import type { z } from 'zod';
import {
  keyBetween,
  type AddIssueLabelCommandSchema,
  type CreateCommentCommandSchema,
  type CreateIssueCommandSchema,
  type DeleteIssueCommandSchema,
  type MoveIssueCommandSchema,
  type RemoveIssueLabelCommandSchema,
  type UpdateIssueCommandSchema,
} from '@linear/shared';
import { Issue, Prisma } from '@prisma/client';
import { OpDraft } from '../sync/sync.service';
import { toCommentPayload, toIssuePayload } from '../sync/payloads';

type Tx = Prisma.TransactionClient;
type CreateIssueCommand = z.infer<typeof CreateIssueCommandSchema>;
type UpdateIssueCommand = z.infer<typeof UpdateIssueCommandSchema>;
type MoveIssueCommand = z.infer<typeof MoveIssueCommandSchema>;
type DeleteIssueCommand = z.infer<typeof DeleteIssueCommandSchema>;
type CreateCommentCommand = z.infer<typeof CreateCommentCommandSchema>;
type AddIssueLabelCommand = z.infer<typeof AddIssueLabelCommandSchema>;
type RemoveIssueLabelCommand = z.infer<typeof RemoveIssueLabelCommandSchema>;

@Injectable()
export class IssuesService {
  async createIssue(
    tx: Tx,
    workspaceId: number,
    actorId: number,
    cmd: CreateIssueCommand,
  ): Promise<OpDraft[]> {
    const team = await tx.team.findFirst({
      where: { id: cmd.teamId, workspaceId },
    });
    if (!team) throw new NotFoundException('team not found in workspace');

    const state = cmd.stateId
      ? await tx.workflowState.findFirst({
          where: { id: cmd.stateId, teamId: team.id },
        })
      : await tx.workflowState.findFirst({
          where: { teamId: team.id },
          orderBy: { position: 'asc' },
        });
    if (!state) {
      throw new UnprocessableEntityException(
        'state does not belong to the team',
      );
    }

    if (cmd.assigneeId != null) {
      await this.assertAssignee(tx, workspaceId, cmd.assigneeId);
    }

    const labelIds = [...new Set(cmd.labelIds ?? [])];
    if (labelIds.length > 0) {
      const labels = await tx.label.findMany({
        where: { id: { in: labelIds }, teamId: team.id },
      });
      if (labels.length !== labelIds.length) {
        throw new UnprocessableEntityException(
          'label does not belong to the team',
        );
      }
    }

    // per-team issue number (ENG-42) の原子採番。
    // ロック順序は workspace (mutations.service が採番ロック済み) → team の一方向
    const counterRows = await tx.$queryRaw<
      Array<{ issue_counter: bigint }>
    >`SELECT issue_counter FROM teams WHERE id = ${team.id} FOR UPDATE`;
    const number = Number(counterRows[0]?.issue_counter ?? 0n) + 1;
    await tx.team.update({
      where: { id: team.id },
      data: { issueCounter: BigInt(number) },
    });

    const sortOrder =
      cmd.sortOrder ?? (await this.appendOrderKey(tx, team.id, state.id));

    const issue = await tx.issue.create({
      data: {
        teamId: team.id,
        number,
        title: cmd.title,
        description: cmd.description ?? null,
        stateId: state.id,
        priority: cmd.priority ?? 0,
        assigneeId: cmd.assigneeId ?? null,
        sortOrder,
        createdById: actorId,
      },
    });

    const drafts: OpDraft[] = [
      {
        entityType: 'issue',
        entityId: issue.id,
        action: 'insert',
        payload: toIssuePayload(issue),
      },
    ];
    for (const labelId of labelIds.sort((a, b) => a - b)) {
      await tx.issueLabel.create({ data: { issueId: issue.id, labelId } });
      drafts.push({
        entityType: 'issue_label',
        entityId: issue.id,
        action: 'insert',
        payload: { issueId: issue.id, labelId },
      });
    }
    return drafts;
  }

  async updateIssue(
    tx: Tx,
    workspaceId: number,
    cmd: UpdateIssueCommand,
  ): Promise<OpDraft[]> {
    const issue = await this.getIssueInWorkspace(tx, workspaceId, cmd.issueId);

    const data: Prisma.IssueUncheckedUpdateInput = {};
    if (cmd.patch.title !== undefined) data.title = cmd.patch.title;
    if (cmd.patch.description !== undefined)
      data.description = cmd.patch.description;
    if (cmd.patch.priority !== undefined) data.priority = cmd.patch.priority;
    if (cmd.patch.assigneeId !== undefined) {
      if (cmd.patch.assigneeId !== null) {
        await this.assertAssignee(tx, workspaceId, cmd.patch.assigneeId);
      }
      data.assigneeId = cmd.patch.assigneeId;
    }
    if (cmd.patch.stateId !== undefined) {
      await this.assertStateInTeam(tx, issue.teamId, cmd.patch.stateId);
      data.stateId = cmd.patch.stateId;
    }

    const updated = await tx.issue.update({
      where: { id: issue.id },
      data,
    });
    return [
      {
        entityType: 'issue',
        entityId: issue.id,
        action: 'update',
        payload: { ...cmd.patch, updatedAt: updated.updatedAt.toISOString() },
      },
    ];
  }

  async moveIssue(
    tx: Tx,
    workspaceId: number,
    cmd: MoveIssueCommand,
  ): Promise<OpDraft[]> {
    const issue = await this.getIssueInWorkspace(tx, workspaceId, cmd.issueId);
    await this.assertStateInTeam(tx, issue.teamId, cmd.stateId);

    const updated = await tx.issue.update({
      where: { id: issue.id },
      data: { stateId: cmd.stateId, sortOrder: cmd.sortOrder },
    });
    return [
      {
        entityType: 'issue',
        entityId: issue.id,
        action: 'update',
        payload: {
          stateId: cmd.stateId,
          sortOrder: cmd.sortOrder,
          updatedAt: updated.updatedAt.toISOString(),
        },
      },
    ];
  }

  /**
   * 削除はカスケード (comments / issue_labels) を DB の FK に任せ、op は issue 1 件のみ。
   * client reducer 側も issue delete を受けたら配下を併せて落とす規約 (shared 側 Phase 4)。
   */
  async deleteIssue(
    tx: Tx,
    workspaceId: number,
    cmd: DeleteIssueCommand,
  ): Promise<OpDraft[]> {
    const issue = await this.getIssueInWorkspace(tx, workspaceId, cmd.issueId);
    await tx.issue.delete({ where: { id: issue.id } });
    return [
      {
        entityType: 'issue',
        entityId: issue.id,
        action: 'delete',
        payload: { id: issue.id },
      },
    ];
  }

  async createComment(
    tx: Tx,
    workspaceId: number,
    actorId: number,
    cmd: CreateCommentCommand,
  ): Promise<OpDraft[]> {
    const issue = await this.getIssueInWorkspace(tx, workspaceId, cmd.issueId);
    const comment = await tx.comment.create({
      data: { issueId: issue.id, authorId: actorId, body: cmd.body },
    });
    return [
      {
        entityType: 'comment',
        entityId: comment.id,
        action: 'insert',
        payload: toCommentPayload(comment),
      },
    ];
  }

  async addIssueLabel(
    tx: Tx,
    workspaceId: number,
    cmd: AddIssueLabelCommand,
  ): Promise<OpDraft[]> {
    const issue = await this.getIssueInWorkspace(tx, workspaceId, cmd.issueId);
    const label = await tx.label.findFirst({
      where: { id: cmd.labelId, teamId: issue.teamId },
    });
    if (!label) {
      throw new UnprocessableEntityException(
        'label does not belong to the team',
      );
    }
    const dup = await tx.issueLabel.findUnique({
      where: { issueId_labelId: { issueId: issue.id, labelId: label.id } },
    });
    if (dup) throw new ConflictException('label already attached');

    await tx.issueLabel.create({
      data: { issueId: issue.id, labelId: label.id },
    });
    return [
      {
        entityType: 'issue_label',
        entityId: issue.id,
        action: 'insert',
        payload: { issueId: issue.id, labelId: label.id },
      },
    ];
  }

  async removeIssueLabel(
    tx: Tx,
    workspaceId: number,
    cmd: RemoveIssueLabelCommand,
  ): Promise<OpDraft[]> {
    const issue = await this.getIssueInWorkspace(tx, workspaceId, cmd.issueId);
    const existing = await tx.issueLabel.findUnique({
      where: { issueId_labelId: { issueId: issue.id, labelId: cmd.labelId } },
    });
    if (!existing) throw new NotFoundException('label not attached');

    await tx.issueLabel.delete({
      where: { issueId_labelId: { issueId: issue.id, labelId: cmd.labelId } },
    });
    return [
      {
        entityType: 'issue_label',
        entityId: issue.id,
        action: 'delete',
        payload: { issueId: issue.id, labelId: cmd.labelId },
      },
    ];
  }

  /** issue が workspace 配下 (team 経由) にあることを認可境界として検証する */
  private async getIssueInWorkspace(
    tx: Tx,
    workspaceId: number,
    issueId: number,
  ): Promise<Issue> {
    const issue = await tx.issue.findFirst({
      where: { id: issueId, team: { workspaceId } },
    });
    if (!issue) throw new NotFoundException('issue not found in workspace');
    return issue;
  }

  private async assertStateInTeam(
    tx: Tx,
    teamId: number,
    stateId: number,
  ): Promise<void> {
    const state = await tx.workflowState.findFirst({
      where: { id: stateId, teamId },
    });
    if (!state) {
      throw new UnprocessableEntityException(
        'state does not belong to the team',
      );
    }
  }

  private async assertAssignee(
    tx: Tx,
    workspaceId: number,
    userId: number,
  ): Promise<void> {
    const member = await tx.workspaceMember.findUnique({
      where: { workspaceId_userId: { workspaceId, userId } },
    });
    if (!member) {
      throw new UnprocessableEntityException(
        'assignee is not a workspace member',
      );
    }
  }

  /** 列末尾に追加する order key (省略時のデフォルト) */
  private async appendOrderKey(
    tx: Tx,
    teamId: number,
    stateId: number,
  ): Promise<string> {
    const last = await tx.issue.findFirst({
      where: { teamId, stateId },
      orderBy: { sortOrder: 'desc' },
      select: { sortOrder: true },
    });
    return keyBetween(last?.sortOrder ?? null, null);
  }
}
