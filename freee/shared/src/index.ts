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

const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'date must be YYYY-MM-DD');

/** money 文字列を整数 cent に変換 (借方=貸方 をブラウザでも判定するため)。 */
export function moneyToCents(v: string): number {
  const parts = v.split('.');
  const int = parts[0] ?? '0';
  const frac = (parts[1] ?? '') + '00';
  return Number(int) * 100 + Number(frac.slice(0, 2));
}

export const journalLineInputSchema = z.object({
  accountId: z.number().int().positive(),
  side: sideSchema,
  amount: moneySchema,
});
export type JournalLineInput = z.infer<typeof journalLineInputSchema>;

/**
 * 仕訳作成。借方合計 = 貸方合計 を refine で FE/BE 共通に検証する (ADR 0002 / 0004)。
 * DB 側 DEFERRABLE trigger が最終防衛線、これは入口の親切なエラー。
 */
export const createJournalEntrySchema = z
  .object({
    entryDate: isoDate,
    description: z.string().max(200).optional(),
    lines: z.array(journalLineInputSchema).min(2),
  })
  .refine(
    (e) => {
      const debit = e.lines
        .filter((l) => l.side === 'debit')
        .reduce((s, l) => s + moneyToCents(l.amount), 0);
      const credit = e.lines
        .filter((l) => l.side === 'credit')
        .reduce((s, l) => s + moneyToCents(l.amount), 0);
      return debit === credit;
    },
    { message: '借方合計と貸方合計が一致しません', path: ['lines'] },
  );
export type CreateJournalEntry = z.infer<typeof createJournalEntrySchema>;

export const reverseEntrySchema = z.object({
  entryDate: isoDate.optional(),
});
export type ReverseEntry = z.infer<typeof reverseEntrySchema>;

export const createPeriodSchema = z
  .object({
    name: z.string().min(1).max(50),
    startsOn: isoDate,
    endsOn: isoDate,
  })
  .refine((e) => e.startsOn <= e.endsOn, {
    message: 'startsOn must be <= endsOn',
    path: ['endsOn'],
  });
export type CreatePeriod = z.infer<typeof createPeriodSchema>;
