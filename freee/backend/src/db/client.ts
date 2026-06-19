import pg from 'pg';

/**
 * 実行時の接続プール。アプリは **非特権ロール freee_app** で接続する (ADR 0001)。
 * superuser / テーブル所有者は RLS をバイパスするため、必ず freee_app を使うこと。
 * マイグレーション (テーブル所有者 freee) は src/db/migrate.ts が別ロールで行う。
 */
export const pool = new pg.Pool({
  connectionString:
    process.env.DATABASE_URL ??
    'postgres://freee_app:freee_app@localhost:5433/freee_development',
});
