import { z } from 'zod';

/**
 * FE/BE で共有する zod スキーマ (ADR 0004)。
 * backend は @hono/zod-validator の入力検証に、frontend はフォーム検証に同じ定義を使う。
 */

/** 勘定科目の区分 (資産 / 負債 / 純資産 / 収益 / 費用)。 */
export const accountTypeSchema = z.enum([
  'asset',
  'liability',
  'equity',
  'revenue',
  'expense',
]);
export type AccountType = z.infer<typeof accountTypeSchema>;

/** 仕訳の借方 / 貸方。 */
export const sideSchema = z.enum(['debit', 'credit']);
export type Side = z.infer<typeof sideSchema>;

/**
 * 金額は NUMERIC(18,2)。JS の number は丸め誤差で借方≠貸方を生むため使わない (ADR 0002 / 0004)。
 * FE/BE 境界では十進文字列で運ぶ。
 */
export const moneySchema = z
  .string()
  .regex(/^\d+(\.\d{1,2})?$/, 'amount must be a positive decimal string (max 2 dp)')
  .refine((v) => Number(v) > 0, 'amount must be greater than 0');

export const createAccountSchema = z.object({
  code: z.string().min(1).max(20),
  name: z.string().min(1).max(100),
  type: accountTypeSchema,
});
export type CreateAccount = z.infer<typeof createAccountSchema>;
