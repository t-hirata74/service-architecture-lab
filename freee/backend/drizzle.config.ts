import { defineConfig } from 'drizzle-kit';

/**
 * Drizzle はクエリ時の型に使う (schema.ts)。
 * RLS ポリシー / EXCLUDE 制約 / constraint trigger は ORM では表現できないため、
 * drizzle/0000_init.sql に生 SQL で書き、src/db/migrate.ts で適用する (ADR 0001-0003)。
 */
export default defineConfig({
  schema: './src/db/schema.ts',
  out: './drizzle',
  dialect: 'postgresql',
  dbCredentials: {
    url:
      process.env.DATABASE_ADMIN_URL ??
      'postgres://freee:freee@localhost:5433/freee_development',
  },
});
