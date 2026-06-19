import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import pg from 'pg';

/**
 * 生 SQL マイグレーション/seed の適用スクリプト。
 *
 * RLS ポリシー / EXCLUDE 制約 / constraint trigger / ロール作成は ORM では表現できないため、
 * drizzle/*.sql を **テーブル所有者 freee (= migration ロール)** として適用する (ADR 0001)。
 * 実行時アプリは別の非特権ロール freee_app を使う (src/db/client.ts)。
 *
 * usage: tsx src/db/migrate.ts <path-to-sql>
 */
const file = process.argv[2];
if (!file) {
  // eslint-disable-next-line no-console
  console.error('usage: tsx src/db/migrate.ts <path-to-sql>');
  process.exit(1);
}

const url =
  process.env.DATABASE_ADMIN_URL ??
  'postgres://freee:freee@localhost:5433/freee_development';

const sql = readFileSync(resolve(file), 'utf8');

const client = new pg.Client({ connectionString: url });
await client.connect();
try {
  await client.query(sql);
  // eslint-disable-next-line no-console
  console.log(`applied ${file}`);
} finally {
  await client.end();
}
