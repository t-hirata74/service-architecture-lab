import { ForbiddenException, Injectable } from '@nestjs/common';
import { WorkspaceMember } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

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
}
