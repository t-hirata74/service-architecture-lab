/**
 * Phase 2 スモーク: ADR 0001-0003 の不変条件が DB 層で効いていることを、
 * 実行時と同じ非特権ロール freee_app で確認する。
 *
 *   tsx scripts/smoke.ts   (docker compose up -d db && db:migrate && db:seed の後)
 */
import pg from 'pg';

const pool = new pg.Pool({
  connectionString:
    process.env.DATABASE_URL ??
    'postgres://freee_app:freee_app@localhost:5433/freee_development',
});

async function asCompany<T>(
  companyId: number | null,
  fn: (c: pg.PoolClient) => Promise<T>,
): Promise<T> {
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    if (companyId !== null) {
      await c.query("SELECT set_config('app.current_company', $1, true)", [String(companyId)]);
    }
    return await fn(c);
  } finally {
    await c.query('ROLLBACK').catch(() => {});
    c.release();
  }
}

const firstLine = (e: unknown) => String(e instanceof Error ? e.message : e).split('\n')[0];

// 1. RLS テナント分離
const c1 = await asCompany(1, (c) => c.query('SELECT code FROM accounts ORDER BY code'));
const c2 = await asCompany(2, (c) => c.query('SELECT code FROM accounts ORDER BY code'));
const c0 = await asCompany(null, (c) => c.query('SELECT code FROM accounts'));
console.log('1. company=1 accounts:', c1.rows.map((r) => r.code).join(','));
console.log('1. company=2 accounts:', c2.rows.map((r) => r.code).join(','));
console.log('1. no-GUC accounts (fail-closed → 0):', c0.rows.length);

// 2. 越境参照: company=1 から company=2 の仕訳 (id=2) は見えない
const cross = await asCompany(1, (c) => c.query('SELECT id FROM journal_entries WHERE id = 2'));
console.log('2. company=1 sees company=2 entry id=2? rows:', cross.rows.length, '(期待: 0)');

// 3. append-only: 記帳済み仕訳の UPDATE は trigger で拒否
let appendOnly = 'NOT rejected (BUG)';
try {
  await asCompany(1, (c) => c.query("UPDATE journal_entries SET description = 'x' WHERE id = 1"));
} catch (e) {
  appendOnly = firstLine(e);
}
console.log('3. append-only UPDATE:', appendOnly);

// 4. 借方≠貸方 は COMMIT 時 (deferred) に拒否
let unbalanced = 'NOT rejected (BUG)';
{
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    await c.query("SELECT set_config('app.current_company', '1', true)");
    const e = await c.query(
      "INSERT INTO journal_entries (company_id, entry_date, description) VALUES (1, '2026-05-01', 'smoke unbalanced') RETURNING id",
    );
    const eid = e.rows[0].id;
    const acc = await c.query("SELECT id FROM accounts WHERE company_id = 1 AND code = '1110'");
    await c.query(
      "INSERT INTO journal_lines (company_id, journal_entry_id, account_id, side, amount) VALUES (1, $1, $2, 'debit', 100.00)",
      [eid, acc.rows[0].id],
    );
    await c.query('COMMIT'); // 貸方が無い → deferred trigger がここで abort
  } catch (e) {
    unbalanced = firstLine(e);
    await c.query('ROLLBACK').catch(() => {});
  } finally {
    c.release();
  }
}
console.log('4. unbalanced COMMIT:', unbalanced);

// 5. 期間外への記帳は拒否 (covering period 無し)
let noPeriod = 'NOT rejected (BUG)';
try {
  await asCompany(1, (c) =>
    c.query(
      "INSERT INTO journal_entries (company_id, entry_date, description) VALUES (1, '2099-01-01', 'smoke no-period')",
    ),
  );
} catch (e) {
  noPeriod = firstLine(e);
}
console.log('5. posting outside any period:', noPeriod);

await pool.end();
