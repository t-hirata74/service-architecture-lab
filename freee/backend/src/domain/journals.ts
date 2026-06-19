import { and, desc, eq, inArray, lte, gte, sql } from 'drizzle-orm';
import type { NodePgDatabase } from 'drizzle-orm/node-postgres';
import type { CreateJournalEntry } from '@freee/shared';
import * as schema from '../db/schema';
import { DomainError } from './errors';

type DB = NodePgDatabase<typeof schema>;

/** entry_date を含む会計期間が存在し open であることを保証する (ADR 0003、trigger は backstop)。 */
async function assertPeriodOpen(db: DB, entryDate: string): Promise<void> {
  const rows = await db
    .select({ status: schema.accountingPeriods.status })
    .from(schema.accountingPeriods)
    .where(
      and(
        lte(schema.accountingPeriods.startsOn, entryDate),
        gte(schema.accountingPeriods.endsOn, entryDate),
      ),
    )
    .limit(1);
  const period = rows[0];
  if (!period) throw new DomainError(422, `記帳日 ${entryDate} を含む会計期間がありません`);
  if (period.status !== 'open') {
    throw new DomainError(422, `記帳日 ${entryDate} の会計期間は ${period.status} です`);
  }
}

export async function listJournalEntries(db: DB) {
  const entries = await db
    .select()
    .from(schema.journalEntries)
    .orderBy(desc(schema.journalEntries.id));
  const lines = await db.select().from(schema.journalLines);
  return entries.map((e) => ({
    ...e,
    lines: lines.filter((l) => l.journalEntryId === e.id),
  }));
}

export async function postJournalEntry(db: DB, companyId: number, input: CreateJournalEntry) {
  await assertPeriodOpen(db, input.entryDate);

  // line が参照する account が自テナントのものか (RLS で他社 account は 0 件になる)。
  const accountIds = [...new Set(input.lines.map((l) => l.accountId))];
  const found = await db
    .select({ id: schema.accounts.id })
    .from(schema.accounts)
    .where(inArray(schema.accounts.id, accountIds));
  if (found.length !== accountIds.length) {
    throw new DomainError(422, '存在しない、または他テナントの勘定科目が含まれています');
  }

  const entryRows = await db
    .insert(schema.journalEntries)
    .values({ companyId, entryDate: input.entryDate, description: input.description ?? null })
    .returning();
  const entry = entryRows[0];
  if (!entry) throw new DomainError(422, '仕訳の作成に失敗しました');

  await db.insert(schema.journalLines).values(
    input.lines.map((l) => ({
      companyId,
      journalEntryId: entry.id,
      accountId: l.accountId,
      side: l.side,
      amount: l.amount,
    })),
  );

  // 借方=貸方 の DEFERRABLE trigger をレスポンス前に即時検証する (ADR 0002)。
  // これをしないと不均衡は middleware の COMMIT 時 = レスポンス送出後に発覚してしまう。
  await db.execute(sql`SET CONSTRAINTS ALL IMMEDIATE`);

  return { ...entry, lines: input.lines };
}

export async function reverseJournalEntry(
  db: DB,
  companyId: number,
  entryId: number,
  entryDate?: string,
) {
  const origRows = await db
    .select()
    .from(schema.journalEntries)
    .where(eq(schema.journalEntries.id, entryId))
    .limit(1);
  const orig = origRows[0];
  if (!orig) throw new DomainError(404, '仕訳が見つかりません');

  const origLines = await db
    .select()
    .from(schema.journalLines)
    .where(eq(schema.journalLines.journalEntryId, entryId));

  const date = entryDate ?? orig.entryDate;
  await assertPeriodOpen(db, date);

  const revRows = await db
    .insert(schema.journalEntries)
    .values({
      companyId,
      entryDate: date,
      description: `逆仕訳: #${entryId}`,
      reversedEntryId: entryId,
    })
    .returning();
  const rev = revRows[0];
  if (!rev) throw new DomainError(422, '逆仕訳の作成に失敗しました');

  // 借方貸方を入れ替える (元仕訳は balanced なので逆仕訳も balanced)。
  const newLines = origLines.map((l) => ({
    companyId,
    journalEntryId: rev.id,
    accountId: l.accountId,
    side: l.side === 'debit' ? ('credit' as const) : ('debit' as const),
    amount: l.amount,
  }));
  await db.insert(schema.journalLines).values(newLines);
  await db.execute(sql`SET CONSTRAINTS ALL IMMEDIATE`);

  return { ...rev, lines: newLines.map(({ side, accountId, amount }) => ({ side, accountId, amount })) };
}
