-- freee 初期マイグレーション (テーブル所有者 freee として適用 / ADR 0001-0004)
-- RLS / EXCLUDE / constraint trigger は ORM で表現できないため生 SQL で管理する。
-- 冪等性のため IF NOT EXISTS / CREATE OR REPLACE / DROP ... IF EXISTS を多用する。

-- EXCLUDE 制約で int 等値 + 範囲重複を同居させるため (ADR 0003)
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ─────────────────────────────────────────────────────────────────────
-- テーブル
-- ─────────────────────────────────────────────────────────────────────

-- companies はテナントのルート (= tenant 自身)。tenant-owned data ではないため RLS は掛けない。
CREATE TABLE IF NOT EXISTS companies (
  id         bigserial PRIMARY KEY,
  name       text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS accounts (
  id         bigserial PRIMARY KEY,
  company_id bigint NOT NULL REFERENCES companies(id),
  code       text NOT NULL,
  name       text NOT NULL,
  type       text NOT NULL CHECK (type IN ('asset','liability','equity','revenue','expense')),
  UNIQUE (company_id, code)
);
CREATE INDEX IF NOT EXISTS idx_accounts_company ON accounts (company_id);

CREATE TABLE IF NOT EXISTS journal_entries (
  id                bigserial PRIMARY KEY,
  company_id        bigint NOT NULL REFERENCES companies(id),
  entry_date        date NOT NULL,
  description       text,
  reversed_entry_id bigint REFERENCES journal_entries(id),
  created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_journal_entries_company ON journal_entries (company_id, entry_date);

CREATE TABLE IF NOT EXISTS journal_lines (
  id               bigserial PRIMARY KEY,
  company_id       bigint NOT NULL REFERENCES companies(id),
  journal_entry_id bigint NOT NULL REFERENCES journal_entries(id),
  account_id       bigint NOT NULL REFERENCES accounts(id),
  side             text NOT NULL CHECK (side IN ('debit','credit')),
  amount           numeric(18,2) NOT NULL CHECK (amount > 0)
);
CREATE INDEX IF NOT EXISTS idx_journal_lines_company ON journal_lines (company_id);
CREATE INDEX IF NOT EXISTS idx_journal_lines_entry ON journal_lines (journal_entry_id);

CREATE TABLE IF NOT EXISTS accounting_periods (
  id         bigserial PRIMARY KEY,
  company_id bigint NOT NULL REFERENCES companies(id),
  name       text NOT NULL,
  starts_on  date NOT NULL,
  ends_on    date NOT NULL,
  status     text NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed')),
  -- 同一 company 内で会計期間が重ならない (Postgres ネイティブ EXCLUDE / ADR 0003)。
  -- calendly が MySQL で代替に苦労した制約をここでは宣言的に書ける。
  CONSTRAINT accounting_periods_no_overlap
    EXCLUDE USING gist (company_id WITH =, daterange(starts_on, ends_on, '[]') WITH &&)
);
CREATE INDEX IF NOT EXISTS idx_periods_company ON accounting_periods (company_id);

-- 締め操作の append-only 監査 (zoom HostTransfer と同系)
CREATE TABLE IF NOT EXISTS period_closings (
  id         bigserial PRIMARY KEY,
  company_id bigint NOT NULL REFERENCES companies(id),
  period_id  bigint NOT NULL REFERENCES accounting_periods(id),
  action     text NOT NULL CHECK (action IN ('close','reopen')),
  at         timestamptz NOT NULL DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────────────
-- 関数 + トリガ (ADR 0002 / 0003)
-- ─────────────────────────────────────────────────────────────────────

-- append-only: 記帳済み仕訳の UPDATE/DELETE を物理拒否。訂正は逆仕訳で表す (ADR 0002)。
CREATE OR REPLACE FUNCTION freee_forbid_mutation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'append-only: % on % is not allowed (use a reversing entry)', TG_OP, TG_TABLE_NAME
    USING ERRCODE = 'restrict_violation';
END;
$$;

-- 借方合計 = 貸方合計 を entry 単位で検証。DEFERRABLE INITIALLY DEFERRED で COMMIT 時に判定し、
-- 明細を 1 行ずつ INSERT する途中の不均衡を許す (ADR 0002)。
CREATE OR REPLACE FUNCTION freee_check_entry_balanced() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_debit  numeric;
  v_credit numeric;
BEGIN
  SELECT
    COALESCE(SUM(amount) FILTER (WHERE side = 'debit'), 0),
    COALESCE(SUM(amount) FILTER (WHERE side = 'credit'), 0)
    INTO v_debit, v_credit
  FROM journal_lines
  WHERE journal_entry_id = NEW.journal_entry_id;

  IF v_debit <> v_credit THEN
    RAISE EXCEPTION 'journal entry % is unbalanced: debit=% credit=%',
      NEW.journal_entry_id, v_debit, v_credit
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NULL;
END;
$$;

-- 記帳ガード: entry_date を含む会計期間が存在し open であること (ADR 0003)。
CREATE OR REPLACE FUNCTION freee_check_period_open() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_status text;
BEGIN
  SELECT status INTO v_status
  FROM accounting_periods
  WHERE company_id = NEW.company_id
    AND NEW.entry_date BETWEEN starts_on AND ends_on
  LIMIT 1;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'no accounting period covers % for company %', NEW.entry_date, NEW.company_id
      USING ERRCODE = 'check_violation';
  ELSIF v_status <> 'open' THEN
    RAISE EXCEPTION 'accounting period for % is % (posting not allowed)', NEW.entry_date, v_status
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_journal_entries_append_only ON journal_entries;
CREATE TRIGGER trg_journal_entries_append_only
  BEFORE UPDATE OR DELETE ON journal_entries
  FOR EACH ROW EXECUTE FUNCTION freee_forbid_mutation();

DROP TRIGGER IF EXISTS trg_journal_lines_append_only ON journal_lines;
CREATE TRIGGER trg_journal_lines_append_only
  BEFORE UPDATE OR DELETE ON journal_lines
  FOR EACH ROW EXECUTE FUNCTION freee_forbid_mutation();

DROP TRIGGER IF EXISTS trg_journal_entries_period_open ON journal_entries;
CREATE TRIGGER trg_journal_entries_period_open
  BEFORE INSERT ON journal_entries
  FOR EACH ROW EXECUTE FUNCTION freee_check_period_open();

DROP TRIGGER IF EXISTS trg_journal_lines_balanced ON journal_lines;
CREATE CONSTRAINT TRIGGER trg_journal_lines_balanced
  AFTER INSERT ON journal_lines
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION freee_check_entry_balanced();

-- ─────────────────────────────────────────────────────────────────────
-- RLS ポリシー (ADR 0001)
--   GUC app.current_company を読み、未設定なら 0 行 (fail-closed)。
--   WITH CHECK で越境 INSERT/UPDATE も封じる。
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE accounts            ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_entries     ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_lines       ENABLE ROW LEVEL SECURITY;
ALTER TABLE accounting_periods  ENABLE ROW LEVEL SECURITY;
ALTER TABLE period_closings     ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS accounts_tenant ON accounts;
CREATE POLICY accounts_tenant ON accounts
  USING      (company_id = NULLIF(current_setting('app.current_company', true), '')::bigint)
  WITH CHECK (company_id = NULLIF(current_setting('app.current_company', true), '')::bigint);

DROP POLICY IF EXISTS journal_entries_tenant ON journal_entries;
CREATE POLICY journal_entries_tenant ON journal_entries
  USING      (company_id = NULLIF(current_setting('app.current_company', true), '')::bigint)
  WITH CHECK (company_id = NULLIF(current_setting('app.current_company', true), '')::bigint);

DROP POLICY IF EXISTS journal_lines_tenant ON journal_lines;
CREATE POLICY journal_lines_tenant ON journal_lines
  USING      (company_id = NULLIF(current_setting('app.current_company', true), '')::bigint)
  WITH CHECK (company_id = NULLIF(current_setting('app.current_company', true), '')::bigint);

DROP POLICY IF EXISTS accounting_periods_tenant ON accounting_periods;
CREATE POLICY accounting_periods_tenant ON accounting_periods
  USING      (company_id = NULLIF(current_setting('app.current_company', true), '')::bigint)
  WITH CHECK (company_id = NULLIF(current_setting('app.current_company', true), '')::bigint);

DROP POLICY IF EXISTS period_closings_tenant ON period_closings;
CREATE POLICY period_closings_tenant ON period_closings
  USING      (company_id = NULLIF(current_setting('app.current_company', true), '')::bigint)
  WITH CHECK (company_id = NULLIF(current_setting('app.current_company', true), '')::bigint);

-- ─────────────────────────────────────────────────────────────────────
-- 実行時アプリ用の非特権ロール (ADR 0001)
--   NOSUPERUSER + NOBYPASSRLS にしないと RLS が効かない。
--   append-only は trigger が強制するので UPDATE/DELETE 権限を持っていてもよい。
-- ─────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'freee_app') THEN
    CREATE ROLE freee_app LOGIN PASSWORD 'freee_app' NOSUPERUSER NOBYPASSRLS;
  END IF;
END
$$;

GRANT USAGE ON SCHEMA public TO freee_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO freee_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO freee_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO freee_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO freee_app;
