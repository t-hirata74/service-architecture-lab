-- datadog Phase 2: 初期スキーマ (ADR 0003/0004)。
-- schema_migrations は migrate runner が作成する。集計列は予約語/関数名を避け *_val で命名。

CREATE TABLE users (
  id            BIGINT AUTO_INCREMENT PRIMARY KEY,
  email         VARCHAR(255) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  created_at    DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  UNIQUE KEY uniq_users_email (email)
);

-- ingest (machine) 経路の API key。key_hash = sha256 hex (ADR 0004)。
CREATE TABLE api_keys (
  id         BIGINT AUTO_INCREMENT PRIMARY KEY,
  name       VARCHAR(255) NOT NULL,
  key_hash   CHAR(64)     NOT NULL,
  created_at DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  UNIQUE KEY uniq_api_keys_hash (key_hash)
);

-- series registry: cardinality 管理 + query 列挙 (ADR 0002/0003)。
-- series_key = sha256 hex(metric_name + sorted tags)。
CREATE TABLE series (
  id          BIGINT AUTO_INCREMENT PRIMARY KEY,
  series_key  CHAR(64)     NOT NULL,
  metric_name VARCHAR(255) NOT NULL,
  tags        JSON         NOT NULL,
  type        VARCHAR(16)  NOT NULL,
  first_seen  DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  last_seen   DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  UNIQUE KEY uniq_series_key (series_key),
  KEY idx_series_metric (metric_name)
);

-- 固定窓 rollup。UNIQUE(series_key, bucket_ts, resolution_s) で flush を冪等 upsert (ADR 0003)。
CREATE TABLE rollups (
  id           BIGINT AUTO_INCREMENT PRIMARY KEY,
  series_key   CHAR(64)    NOT NULL,
  bucket_ts    DATETIME(6) NOT NULL,
  resolution_s INT         NOT NULL,
  cnt          BIGINT      NOT NULL DEFAULT 0,
  sum_val      DOUBLE      NOT NULL DEFAULT 0,
  min_val      DOUBLE      NOT NULL,
  max_val      DOUBLE      NOT NULL,
  last_val     DOUBLE      NOT NULL,
  hist         JSON        NULL,
  UNIQUE KEY uniq_rollup (series_key, bucket_ts, resolution_s),
  KEY idx_rollup_query (series_key, bucket_ts)
);

-- alert rule (ADR 0004)。
CREATE TABLE alert_rules (
  id           BIGINT AUTO_INCREMENT PRIMARY KEY,
  owner_id     BIGINT       NOT NULL,
  name         VARCHAR(255) NOT NULL,
  metric_name  VARCHAR(255) NOT NULL,
  tag_matchers JSON         NOT NULL,
  comparator   VARCHAR(4)   NOT NULL,
  threshold    DOUBLE       NOT NULL,
  window_s     INT          NOT NULL,
  for_s        INT          NOT NULL DEFAULT 0,
  agg          VARCHAR(8)   NOT NULL DEFAULT 'avg',
  dynamic      TINYINT(1)   NOT NULL DEFAULT 0,
  enabled      TINYINT(1)   NOT NULL DEFAULT 1,
  created_at   DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  KEY idx_rule_enabled (enabled),
  CONSTRAINT fk_rule_owner FOREIGN KEY (owner_id) REFERENCES users (id)
);

-- append-only alert state 遷移履歴 (ADR 0004)。
CREATE TABLE alert_events (
  id         BIGINT AUTO_INCREMENT PRIMARY KEY,
  rule_id    BIGINT       NOT NULL,
  state      VARCHAR(16)  NOT NULL,
  value      DOUBLE       NOT NULL,
  created_at DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  KEY idx_event_rule (rule_id, id),
  CONSTRAINT fk_event_rule FOREIGN KEY (rule_id) REFERENCES alert_rules (id)
);
