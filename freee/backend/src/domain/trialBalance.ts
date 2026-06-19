import { sql } from 'drizzle-orm';
import type { NodePgDatabase } from 'drizzle-orm/node-postgres';
import * as schema from '../db/schema';

type DB = NodePgDatabase<typeof schema>;

type TrialBalanceRow = {
  account_id: string;
  code: string;
  name: string;
  type: string;
  debit: string;
  credit: string;
};

/**
 * 試算表: 勘定科目別に借方/貸方を集計する。仕訳の projection なので集計テーブルは持たない。
 * RLS により accounts / journal_lines は現テナント分だけが見えるので、自動的に自社の試算表になる。
 * 全社で借方合計 = 貸方合計 (ADR 0002 の不変条件) が成り立つ。
 */
export async function computeTrialBalance(db: DB) {
  const result = await db.execute<TrialBalanceRow>(sql`
    SELECT a.id AS account_id, a.code, a.name, a.type,
           COALESCE(SUM(l.amount) FILTER (WHERE l.side = 'debit'), 0)  AS debit,
           COALESCE(SUM(l.amount) FILTER (WHERE l.side = 'credit'), 0) AS credit
      FROM accounts a
      LEFT JOIN journal_lines l ON l.account_id = a.id
     GROUP BY a.id, a.code, a.name, a.type
     ORDER BY a.code
  `);

  const accounts = result.rows.map((r) => {
    const debit = Number(r.debit);
    const credit = Number(r.credit);
    return {
      accountId: Number(r.account_id),
      code: r.code,
      name: r.name,
      type: r.type,
      debit: r.debit,
      credit: r.credit,
      balance: (debit - credit).toFixed(2),
    };
  });

  const totalDebitCents = accounts.reduce((s, a) => s + Math.round(Number(a.debit) * 100), 0);
  const totalCreditCents = accounts.reduce((s, a) => s + Math.round(Number(a.credit) * 100), 0);

  return {
    accounts,
    totalDebit: (totalDebitCents / 100).toFixed(2),
    totalCredit: (totalCreditCents / 100).toFixed(2),
    balanced: totalDebitCents === totalCreditCents,
  };
}
