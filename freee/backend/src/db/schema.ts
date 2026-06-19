import {
  pgTable,
  bigserial,
  bigint,
  text,
  date,
  numeric,
  timestamp,
} from 'drizzle-orm/pg-core';

/**
 * クエリ時の型のための Drizzle スキーマ。
 * 実際の制約 (RLS / EXCLUDE / 借方=貸方 trigger / append-only / 期間ガード) は
 * drizzle/0000_init.sql 側の生 SQL が真実 (ADR 0001-0003)。
 */

export const companies = pgTable('companies', {
  id: bigserial('id', { mode: 'number' }).primaryKey(),
  name: text('name').notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
});

export const accounts = pgTable('accounts', {
  id: bigserial('id', { mode: 'number' }).primaryKey(),
  companyId: bigint('company_id', { mode: 'number' }).notNull(),
  code: text('code').notNull(),
  name: text('name').notNull(),
  type: text('type').notNull(), // asset / liability / equity / revenue / expense
});

export const journalEntries = pgTable('journal_entries', {
  id: bigserial('id', { mode: 'number' }).primaryKey(),
  companyId: bigint('company_id', { mode: 'number' }).notNull(),
  entryDate: date('entry_date').notNull(),
  description: text('description'),
  reversedEntryId: bigint('reversed_entry_id', { mode: 'number' }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
});

export const journalLines = pgTable('journal_lines', {
  id: bigserial('id', { mode: 'number' }).primaryKey(),
  companyId: bigint('company_id', { mode: 'number' }).notNull(),
  journalEntryId: bigint('journal_entry_id', { mode: 'number' }).notNull(),
  accountId: bigint('account_id', { mode: 'number' }).notNull(),
  side: text('side').notNull(), // debit / credit
  amount: numeric('amount', { precision: 18, scale: 2 }).notNull(), // 文字列で返る
});

export const accountingPeriods = pgTable('accounting_periods', {
  id: bigserial('id', { mode: 'number' }).primaryKey(),
  companyId: bigint('company_id', { mode: 'number' }).notNull(),
  name: text('name').notNull(),
  startsOn: date('starts_on').notNull(),
  endsOn: date('ends_on').notNull(),
  status: text('status').notNull().default('open'), // open / closed
});

export const periodClosings = pgTable('period_closings', {
  id: bigserial('id', { mode: 'number' }).primaryKey(),
  companyId: bigint('company_id', { mode: 'number' }).notNull(),
  periodId: bigint('period_id', { mode: 'number' }).notNull(),
  action: text('action').notNull(), // close / reopen
  at: timestamp('at', { withTimezone: true }).defaultNow(),
});
