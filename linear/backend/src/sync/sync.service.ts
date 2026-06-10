import { Injectable, NotFoundException } from '@nestjs/common';
import type {
  BootstrapResponse,
  DeltaResponse,
  EntityType,
  OpAction,
  SyncOp,
} from '@linear/shared';
import { Prisma, SyncOp as SyncOpRow } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import {
  toCommentPayload,
  toIssuePayload,
  toLabelPayload,
  toStatePayload,
  toTeamPayload,
} from './payloads';

type Tx = Prisma.TransactionClient;

/** ドメイン処理が生成する「seq 採番前の op」 */
export interface OpDraft {
  entityType: EntityType;
  entityId: number;
  action: OpAction;
  payload: Record<string, unknown>;
}

/**
 * sync log の採番・追記・読み出し (ADR 0002)。
 *
 * 書き込み: lockSyncSeq → (ドメイン処理) → appendOps を必ず同一トランザクションで行う。
 * workspace 行ロックを COMMIT まで保持することで commit 順 = seq 順となり、
 * delta 読者 (`seq > since ORDER BY seq`) が gap を踏まないことが保証される。
 * ロック順序は常に workspace → team (issue counter) の一方向で deadlock を避ける。
 *
 * 読み出し: bootstrap / delta は $transaction 一括読み (REPEATABLE READ snapshot) で、
 * 返す lastSyncId と本体が必ず同一時点になるようにする (torn snapshot 防止)。
 */
@Injectable()
export class SyncService {
  constructor(private readonly prisma: PrismaService) {}

  /** workspace 行を FOR UPDATE でロックし、現在の sync_seq を返す。txn の先頭で呼ぶこと */
  async lockSyncSeq(tx: Tx, workspaceId: number): Promise<bigint> {
    // Prisma に行ロック API が無いため、採番カウンタの読みだけ生 SQL (ADR 0001)
    const rows = await tx.$queryRaw<
      Array<{ sync_seq: bigint }>
    >`SELECT sync_seq FROM workspaces WHERE id = ${workspaceId} FOR UPDATE`;
    const row = rows[0];
    if (!row) throw new NotFoundException('workspace not found');
    return row.sync_seq;
  }

  /** lockSyncSeq 済みの txn 内で、連続 seq を割り当てて sync_ops に追記する */
  async appendOps(
    tx: Tx,
    args: {
      workspaceId: number;
      baseSeq: bigint;
      actorId: number;
      clientMutationId: string;
      drafts: OpDraft[];
    },
  ): Promise<SyncOp[]> {
    const { workspaceId, baseSeq, actorId, clientMutationId, drafts } = args;
    if (drafts.length === 0) {
      throw new Error('appendOps requires at least one op draft');
    }
    const rows = drafts.map((d, i) => ({
      workspaceId,
      seq: baseSeq + BigInt(i + 1),
      entityType: d.entityType,
      entityId: d.entityId,
      action: d.action,
      payload: d.payload as Prisma.InputJsonValue,
      actorId,
      clientMutationId,
    }));
    await tx.syncOp.createMany({ data: rows });
    await tx.workspace.update({
      where: { id: workspaceId },
      data: { syncSeq: baseSeq + BigInt(drafts.length) },
    });
    return rows.map((r) => ({
      seq: Number(r.seq),
      workspaceId,
      entityType: r.entityType,
      entityId: r.entityId,
      action: r.action,
      payload: r.payload as Record<string, unknown>,
      actorId,
      clientMutationId,
    }));
  }

  /** 冪等 replay 用: 記録済み seq 範囲の op を読み出す */
  async opsInRange(
    db: Tx,
    workspaceId: number,
    firstSeq: bigint,
    lastSeq: bigint,
  ): Promise<SyncOp[]> {
    const rows = await db.syncOp.findMany({
      where: { workspaceId, seq: { gte: firstSeq, lte: lastSeq } },
      orderBy: { seq: 'asc' },
    });
    return rows.map((r) => this.rowToOp(r));
  }

  /** 現在の lastSyncId (WS hello 用) */
  async currentSyncId(workspaceId: number): Promise<number> {
    const ws = await this.prisma.workspace.findUniqueOrThrow({
      where: { id: workspaceId },
      select: { syncSeq: true },
    });
    return Number(ws.syncSeq);
  }

  /**
   * 全量 snapshot + lastSyncId。$transaction の一括読みで全クエリを
   * 同一 REPEATABLE READ snapshot に乗せ、lastSyncId との不整合を防ぐ。
   */
  async bootstrap(workspaceId: number): Promise<BootstrapResponse> {
    const [
      workspace,
      members,
      teams,
      states,
      issues,
      labels,
      issueLabels,
      comments,
    ] = await this.prisma.$transaction([
      this.prisma.workspace.findUniqueOrThrow({ where: { id: workspaceId } }),
      this.prisma.workspaceMember.findMany({
        where: { workspaceId },
        include: { user: true },
        orderBy: { userId: 'asc' },
      }),
      this.prisma.team.findMany({
        where: { workspaceId },
        orderBy: { id: 'asc' },
      }),
      this.prisma.workflowState.findMany({
        where: { team: { workspaceId } },
        orderBy: { id: 'asc' },
      }),
      this.prisma.issue.findMany({
        where: { team: { workspaceId } },
        orderBy: { id: 'asc' },
      }),
      this.prisma.label.findMany({
        where: { team: { workspaceId } },
        orderBy: { id: 'asc' },
      }),
      this.prisma.issueLabel.findMany({
        where: { issue: { team: { workspaceId } } },
        orderBy: [{ issueId: 'asc' }, { labelId: 'asc' }],
      }),
      this.prisma.comment.findMany({
        where: { issue: { team: { workspaceId } } },
        orderBy: { id: 'asc' },
      }),
    ]);

    return {
      workspace: {
        id: workspace.id,
        name: workspace.name,
        urlKey: workspace.urlKey,
      },
      users: members.map((m) => ({ id: m.user.id, name: m.user.name })),
      members: members.map((m) => ({
        workspaceId: m.workspaceId,
        userId: m.userId,
        role: m.role,
      })),
      teams: teams.map(toTeamPayload),
      states: states.map(toStatePayload),
      issues: issues.map(toIssuePayload),
      labels: labels.map(toLabelPayload),
      issueLabels: issueLabels.map((il) => ({
        issueId: il.issueId,
        labelId: il.labelId,
      })),
      comments: comments.map(toCommentPayload),
      lastSyncId: Number(workspace.syncSeq),
    };
  }

  /** since より後の確定 op を seq 順で返す (catch-up / ADR 0002) */
  async delta(workspaceId: number, since: number): Promise<DeltaResponse> {
    const [workspace, rows] = await this.prisma.$transaction([
      this.prisma.workspace.findUniqueOrThrow({
        where: { id: workspaceId },
        select: { syncSeq: true },
      }),
      this.prisma.syncOp.findMany({
        where: { workspaceId, seq: { gt: BigInt(since) } },
        orderBy: { seq: 'asc' },
      }),
    ]);
    return {
      ops: rows.map((r) => this.rowToOp(r)),
      lastSyncId: Number(workspace.syncSeq),
    };
  }

  private rowToOp(r: SyncOpRow): SyncOp {
    return {
      seq: Number(r.seq),
      workspaceId: r.workspaceId,
      entityType: r.entityType,
      entityId: r.entityId,
      action: r.action,
      payload: r.payload as Record<string, unknown>,
      actorId: r.actorId,
      clientMutationId: r.clientMutationId,
    };
  }
}
