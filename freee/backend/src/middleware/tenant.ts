import { createMiddleware } from 'hono/factory';
import { drizzle, type NodePgDatabase } from 'drizzle-orm/node-postgres';
import { pool } from '../db/client';
import * as schema from '../db/schema';

export type AppEnv = {
  Variables: {
    db: NodePgDatabase<typeof schema>;
    companyId: number;
  };
};

/**
 * テナント文脈をリクエストに注入する (ADR 0001 の実体)。
 *
 * - リクエストごとに 1 トランザクションを開き、その中で `set_config('app.current_company', _, true)`
 *   (= SET LOCAL) を発行する。RLS ポリシーはこの GUC を読んでテナントを絞る。
 * - `true` (is_local) によりトランザクション終了で自動リセットされ、プール越しの混線を防ぐ。
 * - GUC 未設定なら RLS は 0 行を返す (fail-closed)。
 *
 * Phase 2 では tenant をヘッダ `x-company-id` で受ける。Phase 4 で認証セッションから解決する。
 */
export const tenant = createMiddleware<AppEnv>(async (c, next) => {
  const raw = c.req.header('x-company-id');
  if (!raw || !/^\d+$/.test(raw)) {
    return c.json({ error: 'missing or invalid x-company-id header' }, 400);
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // SET は parameter を取れないため set_config(..., is_local=true) を使う。
    await client.query("SELECT set_config('app.current_company', $1, true)", [raw]);
    c.set('db', drizzle(client, { schema }));
    c.set('companyId', Number(raw));
    await next();
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
});
