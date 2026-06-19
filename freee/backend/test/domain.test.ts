import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import pg from 'pg';
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import app from '../src/app';
import { pool } from '../src/db/client';

// 統合テスト: 実 Postgres (docker compose up -d db + db:migrate 済み前提) に対して
// Hono の app.request() でフルパス (tenant middleware → RLS → Drizzle → trigger) を叩く。
// seed.sql は TRUNCATE ... RESTART IDENTITY なので id が決定的:
//   companies: acme=1, globex=2
//   accounts:  (1,'1110')=1 (1,'4110')=2 (2,'1110')=3 (2,'5110')=4
//   journal_entries: acme=1, globex=2 / 期間: FY2026(2026-01-01..12-31, open) acme=1 globex=2

const ADMIN =
  process.env.DATABASE_ADMIN_URL ?? 'postgres://freee:freee@localhost:5433/freee_development';
const SEED = readFileSync(resolve('drizzle/seed.sql'), 'utf8');

async function reseed() {
  const c = new pg.Client({ connectionString: ADMIN });
  await c.connect();
  try {
    await c.query(SEED);
  } finally {
    await c.end();
  }
}

function req(path: string, companyId: number, init: RequestInit = {}) {
  return app.request(path, {
    ...init,
    headers: {
      'x-company-id': String(companyId),
      'content-type': 'application/json',
      ...(init.headers ?? {}),
    },
  });
}

const balancedLines = (debitAcc: number, creditAcc: number, amount = '500.00') => ({
  lines: [
    { accountId: debitAcc, side: 'debit', amount },
    { accountId: creditAcc, side: 'credit', amount },
  ],
});

beforeEach(reseed);
afterAll(() => pool.end());

describe('RLS マルチテナント分離 (ADR 0001)', () => {
  it('company は自社の勘定科目のみ見える', async () => {
    const a1 = await (await req('/accounts', 1)).json();
    const a2 = await (await req('/accounts', 2)).json();
    expect(a1.map((a: { code: string }) => a.code).sort()).toEqual(['1110', '4110']);
    expect(a2.map((a: { code: string }) => a.code).sort()).toEqual(['1110', '5110']);
  });

  it('x-company-id ヘッダなしは 400', async () => {
    const r = await app.request('/accounts');
    expect(r.status).toBe(400);
  });

  it('list される仕訳はすべて自社のもの', async () => {
    const entries = await (await req('/journal-entries', 1)).json();
    expect(entries.length).toBeGreaterThan(0);
    expect(entries.every((e: { companyId: number }) => e.companyId === 1)).toBe(true);
  });
});

describe('仕訳記帳 + 借方=貸方 (ADR 0002)', () => {
  it('balanced な仕訳を記帳できる', async () => {
    const r = await req('/journal-entries', 1, {
      method: 'POST',
      body: JSON.stringify({ entryDate: '2026-06-01', description: 't', ...balancedLines(1, 2) }),
    });
    expect(r.status).toBe(201);
  });

  it('借方≠貸方は弾く (zod refine → 400)', async () => {
    const r = await req('/journal-entries', 1, {
      method: 'POST',
      body: JSON.stringify({
        entryDate: '2026-06-01',
        lines: [
          { accountId: 1, side: 'debit', amount: '500.00' },
          { accountId: 2, side: 'credit', amount: '400.00' },
        ],
      }),
    });
    expect(r.status).toBe(400);
  });

  it('他テナントの勘定科目を混ぜると 422', async () => {
    // company1 が account id=3 (globex の現金) を使う
    const r = await req('/journal-entries', 1, {
      method: 'POST',
      body: JSON.stringify({ entryDate: '2026-06-01', ...balancedLines(1, 3) }),
    });
    expect(r.status).toBe(422);
  });

  it('期間外への記帳は 422', async () => {
    const r = await req('/journal-entries', 1, {
      method: 'POST',
      body: JSON.stringify({ entryDate: '2099-01-01', ...balancedLines(1, 2) }),
    });
    expect(r.status).toBe(422);
  });
});

describe('逆仕訳 (ADR 0002)', () => {
  it('借方貸方を反転した逆仕訳を作る', async () => {
    const r = await req('/journal-entries/1/reverse', 1, {
      method: 'POST',
      body: JSON.stringify({ entryDate: '2026-06-02' }),
    });
    expect(r.status).toBe(201);
    const rev = await r.json();
    expect(rev.reversedEntryId).toBe(1);
    // seed entry#1: debit 現金(1) / credit 売上(2) → 逆仕訳: debit 売上(2) / credit 現金(1)
    const debit = rev.lines.find((l: { side: string }) => l.side === 'debit');
    expect(debit.accountId).toBe(2);
  });
});

describe('期末締め state machine + EXCLUDE (ADR 0003)', () => {
  it('open → close → reopen', async () => {
    const closed = await req('/accounting-periods/1/close', 1, { method: 'POST' });
    expect(closed.status).toBe(200);
    expect((await closed.json()).status).toBe('closed');

    const reopened = await req('/accounting-periods/1/reopen', 1, { method: 'POST' });
    expect((await reopened.json()).status).toBe('open');
  });

  it('close 済みを再 close は 409 (不正遷移)', async () => {
    await req('/accounting-periods/1/close', 1, { method: 'POST' });
    const r = await req('/accounting-periods/1/close', 1, { method: 'POST' });
    expect(r.status).toBe(409);
  });

  it('締め済み期間への記帳は 422', async () => {
    await req('/accounting-periods/1/close', 1, { method: 'POST' });
    const r = await req('/journal-entries', 1, {
      method: 'POST',
      body: JSON.stringify({ entryDate: '2026-06-01', ...balancedLines(1, 2) }),
    });
    expect(r.status).toBe(422);
  });

  it('重複する期間の作成は 422 (EXCLUDE)', async () => {
    const r = await req('/accounting-periods', 1, {
      method: 'POST',
      body: JSON.stringify({ name: 'overlap', startsOn: '2026-06-01', endsOn: '2026-07-01' }),
    });
    expect(r.status).toBe(422);
  });

  it('重複しない期間は作成できる', async () => {
    const r = await req('/accounting-periods', 1, {
      method: 'POST',
      body: JSON.stringify({ name: 'FY2027', startsOn: '2027-01-01', endsOn: '2027-12-31' }),
    });
    expect(r.status).toBe(201);
  });
});

describe('試算表 (ADR 0002)', () => {
  it('借方合計 = 貸方合計', async () => {
    const tb = await (await req('/trial-balance', 1)).json();
    expect(tb.balanced).toBe(true);
    expect(tb.totalDebit).toBe(tb.totalCredit);
  });

  it('試算表もテナント分離される (company2 は自社のみ集計)', async () => {
    const tb = await (await req('/trial-balance', 2)).json();
    expect(tb.accounts.map((a: { code: string }) => a.code).sort()).toEqual(['1110', '5110']);
  });
});
