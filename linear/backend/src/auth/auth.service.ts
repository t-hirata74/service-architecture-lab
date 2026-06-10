import {
  ConflictException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { LoginRequest, SignupRequest } from '@linear/shared';
import { Prisma } from '@prisma/client';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../prisma/prisma.service';
import { DEFAULT_WORKFLOW_STATES } from '@linear/shared';

export interface AuthResult {
  token: string;
  user: { id: number; email: string; name: string };
  workspace: { id: number; name: string; urlKey: string };
}

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
  ) {}

  /**
   * signup は user + workspace + 既定 team/states を 1 txn で seed する。
   * この時点ではこの workspace を購読中の client が存在し得ないため、
   * sync_ops は発行しない (以後の参加者は bootstrap で全量を得る / ADR 0002)。
   */
  async signup(dto: SignupRequest): Promise<AuthResult> {
    const passwordHash = await bcrypt.hash(dto.password, 10);
    try {
      const { user, workspace } = await this.prisma.$transaction(async (tx) => {
        const user = await tx.user.create({
          data: { email: dto.email, passwordHash, name: dto.name },
        });
        const workspace = await tx.workspace.create({
          data: {
            name: `${dto.name} Workspace`,
            urlKey: this.urlKey(dto.name, user.id),
          },
        });
        await tx.workspaceMember.create({
          data: {
            workspaceId: workspace.id,
            userId: user.id,
            role: 'admin',
          },
        });
        const team = await tx.team.create({
          data: { workspaceId: workspace.id, key: 'GEN', name: 'General' },
        });
        await tx.workflowState.createMany({
          data: DEFAULT_WORKFLOW_STATES.map((s, i) => ({
            teamId: team.id,
            name: s.name,
            category: s.category,
            position: i,
          })),
        });
        return { user, workspace };
      });
      return {
        token: await this.sign(user.id),
        user: { id: user.id, email: user.email, name: user.name },
        workspace: {
          id: workspace.id,
          name: workspace.name,
          urlKey: workspace.urlKey,
        },
      };
    } catch (e) {
      if (
        e instanceof Prisma.PrismaClientKnownRequestError &&
        e.code === 'P2002'
      ) {
        throw new ConflictException('email already taken');
      }
      throw e;
    }
  }

  async login(dto: LoginRequest): Promise<Omit<AuthResult, 'workspace'>> {
    const user = await this.prisma.user.findUnique({
      where: { email: dto.email },
    });
    if (!user || !(await bcrypt.compare(dto.password, user.passwordHash))) {
      throw new UnauthorizedException('invalid email or password');
    }
    return {
      token: await this.sign(user.id),
      user: { id: user.id, email: user.email, name: user.name },
    };
  }

  async me(userId: number) {
    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      include: { memberships: { include: { workspace: true } } },
    });
    return {
      user: { id: user.id, email: user.email, name: user.name },
      workspaces: user.memberships.map((m) => ({
        id: m.workspace.id,
        name: m.workspace.name,
        urlKey: m.workspace.urlKey,
        role: m.role,
      })),
    };
  }

  private sign(userId: number): Promise<string> {
    return this.jwt.signAsync({ sub: userId });
  }

  private urlKey(name: string, userId: number): string {
    const slug = name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 30);
    return `${slug || 'ws'}-${userId}`;
  }
}
