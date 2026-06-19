import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import {
  createAccountSchema,
  createJournalEntrySchema,
  reverseEntrySchema,
  createPeriodSchema,
} from '@freee/shared';
import { tenant, type AppEnv } from './middleware/tenant';
import { accounts } from './db/schema';
import { DomainError } from './domain/errors';
import * as journals from './domain/journals';
import * as periods from './domain/periods';
import { computeTrialBalance } from './domain/trialBalance';

// pg の SQLSTATE → HTTP。アプリ層を素通りした DB 制約違反 (trigger / EXCLUDE 等) の最終マッピング。
const SQLSTATE_STATUS: Record<string, 409 | 422> = {
  '23514': 422, // check_violation — 借方≠貸方 / 期間ガード trigger
  '23P01': 422, // exclusion_violation — 期間重複 (EXCLUDE)
  '23505': 409, // unique_violation — 勘定科目コード重複
  '23001': 409, // restrict_violation — append-only trigger
  '23503': 422, // foreign_key_violation
};

// Drizzle 0.45 は pg エラーを DrizzleQueryError でラップするため、SQLSTATE は cause 側にある。
// cause チェーンを辿って pg の code を取り出す。
function pgErrorCode(err: unknown): string | undefined {
  let cur: unknown = err;
  for (let depth = 0; depth < 5 && cur; depth++) {
    const code = (cur as { code?: unknown }).code;
    if (typeof code === 'string') return code;
    cur = (cur as { cause?: unknown }).cause;
  }
  return undefined;
}

/**
 * Hono アプリ本体。/health 以外は tenant middleware を通す (`.use('*')` を /health の後に置く)。
 * ルート型から AppType を export し frontend は hc<AppType> で型共有する (ADR 0004)。
 */
const app = new Hono<AppEnv>()
  .onError((err, c) => {
    if (err instanceof DomainError) return c.json({ error: err.message }, err.status);
    const code = pgErrorCode(err);
    if (code && code in SQLSTATE_STATUS) {
      return c.json({ error: err.message }, SQLSTATE_STATUS[code]!);
    }
    // eslint-disable-next-line no-console
    console.error(err);
    return c.json({ error: 'internal error' }, 500);
  })
  .get('/health', (c) => c.json({ status: 'ok' as const }))
  // ↓ ここ以降に登録するルートはすべて tenant 文脈 (SET LOCAL app.current_company) を通る。
  .use('*', tenant)
  // ─ accounts ─
  .get('/accounts', async (c) => c.json(await c.get('db').select().from(accounts)))
  .post('/accounts', zValidator('json', createAccountSchema), async (c) => {
    const rows = await c
      .get('db')
      .insert(accounts)
      .values({ ...c.req.valid('json'), companyId: c.get('companyId') })
      .returning();
    return c.json(rows[0], 201);
  })
  // ─ journal entries (記帳 / 逆仕訳) ─
  .get('/journal-entries', async (c) => c.json(await journals.listJournalEntries(c.get('db'))))
  .post('/journal-entries', zValidator('json', createJournalEntrySchema), async (c) => {
    const row = await journals.postJournalEntry(c.get('db'), c.get('companyId'), c.req.valid('json'));
    return c.json(row, 201);
  })
  .post('/journal-entries/:id/reverse', zValidator('json', reverseEntrySchema), async (c) => {
    const row = await journals.reverseJournalEntry(
      c.get('db'),
      c.get('companyId'),
      Number(c.req.param('id')),
      c.req.valid('json').entryDate,
    );
    return c.json(row, 201);
  })
  // ─ accounting periods (期末締め state machine) ─
  .get('/accounting-periods', async (c) => c.json(await periods.listPeriods(c.get('db'))))
  .post('/accounting-periods', zValidator('json', createPeriodSchema), async (c) => {
    const row = await periods.createPeriod(c.get('db'), c.get('companyId'), c.req.valid('json'));
    return c.json(row, 201);
  })
  .post('/accounting-periods/:id/close', async (c) =>
    c.json(await periods.closePeriod(c.get('db'), c.get('companyId'), Number(c.req.param('id')))),
  )
  .post('/accounting-periods/:id/reopen', async (c) =>
    c.json(await periods.reopenPeriod(c.get('db'), c.get('companyId'), Number(c.req.param('id')))),
  )
  // ─ trial balance (試算表) ─
  .get('/trial-balance', async (c) => c.json(await computeTrialBalance(c.get('db'))));

export type AppType = typeof app;
export default app;
