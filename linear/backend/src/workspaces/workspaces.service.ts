import {
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import type { z } from 'zod';
import type {
  InviteMemberCommandSchema,
  RemoveMemberCommandSchema,
} from '@linear/shared';
import { Prisma, WorkspaceMember } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { OpDraft } from '../sync/sync.service';

type Tx = Prisma.TransactionClient;
type InviteMemberCommand = z.infer<typeof InviteMemberCommandSchema>;
type RemoveMemberCommand = z.infer<typeof RemoveMemberCommandSchema>;

@Injectable()
export class WorkspacesService {
  constructor(private readonly prisma: PrismaService) {}

  /** 認可 1 経路: workspace member であることが全 mutation / 全読み取りの条件 */
  async assertMember(
    workspaceId: number,
    userId: number,
  ): Promise<WorkspaceMember> {
    const member = await this.prisma.workspaceMember.findUnique({
      where: { workspaceId_userId: { workspaceId, userId } },
    });
    if (!member) {
      throw new ForbiddenException('not a member of this workspace');
    }
    return member;
  }

  async listForUser(userId: number) {
    const memberships = await this.prisma.workspaceMember.findMany({
      where: { userId },
      include: { workspace: true },
      orderBy: { workspaceId: 'asc' },
    });
    return memberships.map((m) => ({
      id: m.workspace.id,
      name: m.workspace.name,
      urlKey: m.workspace.urlKey,
      role: m.role,
    }));
  }

  /**
   * 登録済みユーザの email を指定して member に加える (ADR 0006 / admin 限定)。
   * 招待 token / メール送信はローカル完結方針によりスコープ外。
   * op payload に user の表示情報を同梱し、他 client の reducer が
   * members と users の両方を更新できるようにする。
   */
  async inviteMember(
    tx: Tx,
    workspaceId: number,
    actorId: number,
    cmd: InviteMemberCommand,
  ): Promise<OpDraft[]> {
    await this.assertAdmin(tx, workspaceId, actorId);
    const user = await tx.user.findUnique({ where: { email: cmd.email } });
    if (!user) {
      throw new UnprocessableEntityException(
        'no registered user with this email',
      );
    }
    const existing = await tx.workspaceMember.findUnique({
      where: { workspaceId_userId: { workspaceId, userId: user.id } },
    });
    if (existing) throw new ConflictException('already a member');

    const member = await tx.workspaceMember.create({
      data: { workspaceId, userId: user.id, role: cmd.role },
    });
    return [
      {
        entityType: 'workspace_member',
        entityId: user.id,
        action: 'insert',
        payload: {
          workspaceId,
          userId: user.id,
          role: member.role,
          user: { id: user.id, name: user.name },
        },
      },
    ];
  }

  /** admin 限定。自分自身は remove できない (最後の admin を失わないための最小ガード) */
  async removeMember(
    tx: Tx,
    workspaceId: number,
    actorId: number,
    cmd: RemoveMemberCommand,
  ): Promise<OpDraft[]> {
    await this.assertAdmin(tx, workspaceId, actorId);
    if (cmd.userId === actorId) {
      throw new UnprocessableEntityException('cannot remove yourself');
    }
    const member = await tx.workspaceMember.findUnique({
      where: { workspaceId_userId: { workspaceId, userId: cmd.userId } },
    });
    if (!member) throw new NotFoundException('member not found');

    await tx.workspaceMember.delete({
      where: { workspaceId_userId: { workspaceId, userId: cmd.userId } },
    });
    return [
      {
        entityType: 'workspace_member',
        entityId: cmd.userId,
        action: 'delete',
        payload: { userId: cmd.userId },
      },
    ];
  }

  private async assertAdmin(
    tx: Tx,
    workspaceId: number,
    userId: number,
  ): Promise<void> {
    const member = await tx.workspaceMember.findUnique({
      where: { workspaceId_userId: { workspaceId, userId } },
    });
    if (!member || member.role !== 'admin') {
      throw new ForbiddenException('admin role required');
    }
  }
}
