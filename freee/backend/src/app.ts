import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { createAccountSchema } from '@freee/shared';
import { tenant, type AppEnv } from './middleware/tenant';
import { accounts } from './db/schema';

/**
 * Hono アプリ本体。ルート定義から AppType を export し、frontend は hc<AppType> で
 * codegen 無しに型付き呼び出しする (ADR 0004)。
 *
 * Phase 2 はスタック疎通の縦スライスとして accounts (list / create) のみ。
 * 仕訳記帳 / 期末締め / 試算表は Phase 3-4 で追加する。
 */
const app = new Hono<AppEnv>()
  .get('/health', (c) => c.json({ status: 'ok' as const }))
  // accounts は tenant スコープ: middleware が SET LOCAL でテナントを注入し RLS が絞る。
  .use('/accounts', tenant)
  .get('/accounts', async (c) => {
    const db = c.get('db');
    const rows = await db.select().from(accounts);
    return c.json(rows);
  })
  .post('/accounts', zValidator('json', createAccountSchema), async (c) => {
    const db = c.get('db');
    const body = c.req.valid('json');
    const [row] = await db
      .insert(accounts)
      .values({ ...body, companyId: c.get('companyId') })
      .returning();
    return c.json(row, 201);
  });

export type AppType = typeof app;
export default app;
