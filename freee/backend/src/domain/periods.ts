import { and, eq } from 'drizzle-orm';
import type { NodePgDatabase } from 'drizzle-orm/node-postgres';
import type { CreatePeriod } from '@freee/shared';
import * as schema from '../db/schema';
import { DomainError } from './errors';

type DB = NodePgDatabase<typeof schema>;
type Status = 'open' | 'closed';
type Action = 'close' | 'reopen';

// 期末締め state machine (ADR 0003、zoom の TRANSITIONS マップと同型)。
const FROM: Record<Action, Status> = { close: 'open', reopen: 'closed' };
const TO: Record<Action, Status> = { close: 'closed', reopen: 'open' };

export function listPeriods(db: DB) {
  return db.select().from(schema.accountingPeriods).orderBy(schema.accountingPeriods.startsOn);
}

export async function createPeriod(db: DB, companyId: number, input: CreatePeriod) {
  // 期間の重複は EXCLUDE 制約が弾く (exclusion_violation → onError で 422)。
  const rows = await db
    .insert(schema.accountingPeriods)
    .values({
      companyId,
      name: input.name,
      startsOn: input.startsOn,
      endsOn: input.endsOn,
    })
    .returning();
  const period = rows[0];
  if (!period) throw new DomainError(422, '会計期間の作成に失敗しました');
  return period;
}

async function transition(db: DB, companyId: number, periodId: number, action: Action) {
  // compare-and-set: WHERE status = FROM[action] の行だけ進む (並行・冪等。uber/shopify と同型)。
  const updated = await db
    .update(schema.accountingPeriods)
    .set({ status: TO[action] })
    .where(
      and(
        eq(schema.accountingPeriods.id, periodId),
        eq(schema.accountingPeriods.status, FROM[action]),
      ),
    )
    .returning();

  const period = updated[0];
  if (!period) {
    const exists = (
      await db
        .select({ status: schema.accountingPeriods.status })
        .from(schema.accountingPeriods)
        .where(eq(schema.accountingPeriods.id, periodId))
        .limit(1)
    )[0];
    if (!exists) throw new DomainError(404, '会計期間が見つかりません');
    throw new DomainError(409, `状態 ${exists.status} から ${action} はできません`);
  }

  await db.insert(schema.periodClosings).values({ companyId, periodId, action });
  return period;
}

export const closePeriod = (db: DB, companyId: number, periodId: number) =>
  transition(db, companyId, periodId, 'close');
export const reopenPeriod = (db: DB, companyId: number, periodId: number) =>
  transition(db, companyId, periodId, 'reopen');
