import { ConflictException, Injectable } from '@nestjs/common';
import type {
  MutationCommand,
  MutationRequest,
  MutationResponse,
} from '@linear/shared';
import { MutationLedger, Prisma } from '@prisma/client';
import { IssuesService } from '../issues/issues.service';
import { PrismaService } from '../prisma/prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import { OpDraft, SyncService } from '../sync/sync.service';
import { TeamsService } from '../teams/teams.service';
import { WorkspacesService } from '../workspaces/workspaces.service';

type Tx = Prisma.TransactionClient;

/**
 * 書き込みの唯一の入口 (architecture.md)。
 * 1 txn = [workspace 行ロック → ドメイン処理 → sync_ops 追記 → 冪等台帳]。
 * COMMIT 後の WS broadcast は Phase 3 (realtime module) で接続する。
 */
@Injectable()
export class MutationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly workspaces: WorkspacesService,
    private readonly sync: SyncService,
    private readonly teams: TeamsService,
    private readonly issues: IssuesService,
    private readonly realtime: RealtimeService,
  ) {}

  async execute(
    userId: number,
    req: MutationRequest,
  ): Promise<MutationResponse> {
    await this.workspaces.assertMember(req.workspaceId, userId);

    try {
      const { response, fresh } = await this.prisma.$transaction(
        async (tx) => {
          // 冪等性: 既知の clientMutationId は記録済み結果を返す (at-least-once 再送の no-op 化)
          const existing = await tx.mutationLedger.findUnique({
            where: { clientMutationId: req.clientMutationId },
          });
          if (existing) {
            return {
              response: await this.replay(tx, req, existing),
              fresh: false,
            };
          }

          const baseSeq = await this.sync.lockSyncSeq(tx, req.workspaceId);
          const drafts = await this.dispatch(
            tx,
            req.workspaceId,
            userId,
            req.command,
          );
          const ops = await this.sync.appendOps(tx, {
            workspaceId: req.workspaceId,
            baseSeq,
            actorId: userId,
            clientMutationId: req.clientMutationId,
            drafts,
          });
          await tx.mutationLedger.create({
            data: {
              clientMutationId: req.clientMutationId,
              workspaceId: req.workspaceId,
              actorId: userId,
              firstSeq: BigInt(ops[0].seq),
              lastSeq: BigInt(ops[ops.length - 1].seq),
            },
          });
          return {
            response: { ops, lastSyncId: ops[ops.length - 1].seq },
            fresh: true,
          };
        },
        // 書き込みは workspace 行ロックで意図的に直列化される (ADR 0002 のトレードオフ)。
        // 並行 mutation のロック待ち + pool 待ちを見込んで既定値より余裕を持たせる
        { maxWait: 5_000, timeout: 10_000 },
      );

      // COMMIT 後にのみ push する (figma ADR 0003 と同形)。replay は初回実行時に
      // broadcast 済みのため再送しない。push の取りこぼしは delta が吸収する (ADR 0005)
      if (fresh) this.realtime.broadcastOps(req.workspaceId, response.ops);
      return response;
    } catch (e) {
      // 同一 clientMutationId の並行実行: UNIQUE で負けた側は勝者の記録を返す
      if (this.isClientMutationIdConflict(e)) {
        const ledger = await this.prisma.mutationLedger.findUniqueOrThrow({
          where: { clientMutationId: req.clientMutationId },
        });
        return this.replay(this.prisma, req, ledger);
      }
      throw e;
    }
  }

  /** mutations.client_mutation_id UNIQUE 違反 (P2002) かどうか */
  private isClientMutationIdConflict(e: unknown): boolean {
    if (
      !(e instanceof Prisma.PrismaClientKnownRequestError) ||
      e.code !== 'P2002'
    ) {
      return false;
    }
    const target = e.meta?.target;
    const name =
      typeof target === 'string' ? target : (JSON.stringify(target) ?? '');
    return name.includes('client_mutation_id');
  }

  private async replay(
    db: Tx,
    req: MutationRequest,
    ledger: MutationLedger,
  ): Promise<MutationResponse> {
    if (ledger.workspaceId !== req.workspaceId) {
      throw new ConflictException(
        'clientMutationId already used in another workspace',
      );
    }
    const ops = await this.sync.opsInRange(
      db,
      ledger.workspaceId,
      ledger.firstSeq,
      ledger.lastSeq,
    );
    return { ops, lastSyncId: Number(ledger.lastSeq) };
  }

  private dispatch(
    tx: Tx,
    workspaceId: number,
    actorId: number,
    command: MutationCommand,
  ): Promise<OpDraft[]> {
    switch (command.type) {
      case 'createTeam':
        return this.teams.createTeam(tx, workspaceId, command);
      case 'createLabel':
        return this.teams.createLabel(tx, workspaceId, command);
      case 'createIssue':
        return this.issues.createIssue(tx, workspaceId, actorId, command);
      case 'updateIssue':
        return this.issues.updateIssue(tx, workspaceId, command);
      case 'moveIssue':
        return this.issues.moveIssue(tx, workspaceId, command);
      case 'deleteIssue':
        return this.issues.deleteIssue(tx, workspaceId, command);
      case 'createComment':
        return this.issues.createComment(tx, workspaceId, actorId, command);
      case 'addIssueLabel':
        return this.issues.addIssueLabel(tx, workspaceId, command);
      case 'removeIssueLabel':
        return this.issues.removeIssueLabel(tx, workspaceId, command);
    }
  }
}
