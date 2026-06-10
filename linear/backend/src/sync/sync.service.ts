import { Injectable, NotFoundException } from '@nestjs/common';
import type { EntityType, OpAction, SyncOp } from '@linear/shared';
import { Prisma } from '@prisma/client';

type Tx = Prisma.TransactionClient;

/** ドメイン処理が生成する「seq 採番前の op」 */
export interface OpDraft {
  entityType: EntityType;
  entityId: number;
  action: OpAction;
  payload: Record<string, unknown>;
}

/**
 * sync log の採番と追記 (ADR 0002)。
 *
 * lockSyncSeq → (ドメイン処理) → appendOps を必ず同一トランザクションで行う。
 * workspace 行ロックを COMMIT まで保持することで commit 順 = seq 順となり、
 * delta 読者 (`seq > since ORDER BY seq`) が gap を踏まないことが保証される。
 * ロック順序は常に workspace → team (issue counter) の一方向で deadlock を避ける。
 */
@Injectable()
export class SyncService {
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
    return rows.map((r) => ({
      seq: Number(r.seq),
      workspaceId: r.workspaceId,
      entityType: r.entityType,
      entityId: r.entityId,
      action: r.action,
      payload: r.payload as Record<string, unknown>,
      actorId: r.actorId,
      clientMutationId: r.clientMutationId,
    }));
  }
}
