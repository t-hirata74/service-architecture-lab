export const SEED_USER_EMAIL = "alice@example.com";

// 各 spec が一意のタイトルを使うようにするユーティリティ。
export function uniqueTitle(prefix = "E2E"): string {
  const stamp = `${Date.now()}-${Math.floor(Math.random() * 1_000)}`;
  return `${prefix} ${stamp}`;
}
