-- seed (テーブル所有者 freee として適用 = RLS バイパス、複数 company を跨いで投入できる)。
-- 再実行可能なように業務テーブルを TRUNCATE してから入れ直す。
-- TRUNCATE は append-only trigger (BEFORE UPDATE/DELETE) を発火させないので再 seed できる。

TRUNCATE period_closings, journal_lines, journal_entries, accounting_periods, accounts, companies
  RESTART IDENTITY CASCADE;

-- companies: acme (id=1), globex (id=2)
INSERT INTO companies (name) VALUES ('Acme Inc.'), ('Globex LLC');

-- accounts
INSERT INTO accounts (company_id, code, name, type) VALUES
  (1, '1110', '現金',     'asset'),
  (1, '4110', '売上高',   'revenue'),
  (2, '1110', '現金',     'asset'),
  (2, '5110', '地代家賃', 'expense');

-- 会計期間 (2026 年度、open)
INSERT INTO accounting_periods (company_id, name, starts_on, ends_on, status) VALUES
  (1, 'FY2026', '2026-01-01', '2026-12-31', 'open'),
  (2, 'FY2026', '2026-01-01', '2026-12-31', 'open');

-- 仕訳 (借方 = 貸方 / 期間 open を trigger が検証する)
-- acme: 売上 1,000 を現金で受領 (借方 現金 / 貸方 売上高)
INSERT INTO journal_entries (company_id, entry_date, description)
  VALUES (1, '2026-04-01', 'seed: 売上計上');
INSERT INTO journal_lines (company_id, journal_entry_id, account_id, side, amount)
SELECT 1, e.id, a.id, 'debit', 1000.00
  FROM journal_entries e, accounts a
 WHERE e.company_id = 1 AND e.description = 'seed: 売上計上'
   AND a.company_id = 1 AND a.code = '1110';
INSERT INTO journal_lines (company_id, journal_entry_id, account_id, side, amount)
SELECT 1, e.id, a.id, 'credit', 1000.00
  FROM journal_entries e, accounts a
 WHERE e.company_id = 1 AND e.description = 'seed: 売上計上'
   AND a.company_id = 1 AND a.code = '4110';

-- globex: 家賃 500 を現金で支払 (借方 地代家賃 / 貸方 現金)
INSERT INTO journal_entries (company_id, entry_date, description)
  VALUES (2, '2026-04-01', 'seed: 家賃支払');
INSERT INTO journal_lines (company_id, journal_entry_id, account_id, side, amount)
SELECT 2, e.id, a.id, 'debit', 500.00
  FROM journal_entries e, accounts a
 WHERE e.company_id = 2 AND e.description = 'seed: 家賃支払'
   AND a.company_id = 2 AND a.code = '5110';
INSERT INTO journal_lines (company_id, journal_entry_id, account_id, side, amount)
SELECT 2, e.id, a.id, 'credit', 500.00
  FROM journal_entries e, accounts a
 WHERE e.company_id = 2 AND e.description = 'seed: 家賃支払'
   AND a.company_id = 2 AND a.code = '1110';
