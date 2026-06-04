// Package store は database/sql + 生 SQL の薄いラッパ (ORM は使わない、go.md 方針)。
package store

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"github.com/go-sql-driver/mysql"
)

var ErrNotFound = errors.New("store: not found")

type Store struct{ DB *sql.DB }

// Open は *sql.DB を 1 つ開き pool を明示設定する (go.md §7)。
func Open(dsn string) (*Store, error) {
	mc, err := mysql.ParseDSN(dsn)
	if err != nil {
		return nil, err
	}
	mc.ParseTime = true
	db, err := sql.Open("mysql", mc.FormatDSN())
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(20)
	db.SetMaxIdleConns(10)
	db.SetConnMaxLifetime(time.Hour)
	if err := db.Ping(); err != nil {
		db.Close()
		return nil, err
	}
	return &Store{DB: db}, nil
}

// ─── users (dashboard 認証) ─────────────────────────────────────────────────

type User struct {
	ID           int64     `json:"id"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"-"`
	CreatedAt    time.Time `json:"created_at"`
}

func (s *Store) CreateUser(ctx context.Context, email, passwordHash string) (int64, error) {
	res, err := s.DB.ExecContext(ctx,
		`INSERT INTO users (email, password_hash) VALUES (?, ?)`, email, passwordHash)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

func (s *Store) UserByEmail(ctx context.Context, email string) (*User, error) {
	return s.scanUser(s.DB.QueryRowContext(ctx,
		`SELECT id, email, password_hash, created_at FROM users WHERE email = ? LIMIT 1`, email))
}

func (s *Store) UserByID(ctx context.Context, id int64) (*User, error) {
	return s.scanUser(s.DB.QueryRowContext(ctx,
		`SELECT id, email, password_hash, created_at FROM users WHERE id = ? LIMIT 1`, id))
}

func (s *Store) scanUser(row *sql.Row) (*User, error) {
	var u User
	if err := row.Scan(&u.ID, &u.Email, &u.PasswordHash, &u.CreatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &u, nil
}

// ─── api_keys (ingest 認証) ─────────────────────────────────────────────────

type APIKey struct {
	ID        int64     `json:"id"`
	Name      string    `json:"name"`
	KeyHash   string    `json:"-"`
	CreatedAt time.Time `json:"created_at"`
}

func (s *Store) CreateAPIKey(ctx context.Context, name, keyHash string) (int64, error) {
	res, err := s.DB.ExecContext(ctx,
		`INSERT INTO api_keys (name, key_hash) VALUES (?, ?)`, name, keyHash)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

func (s *Store) APIKeyByHash(ctx context.Context, keyHash string) (*APIKey, error) {
	var k APIKey
	err := s.DB.QueryRowContext(ctx,
		`SELECT id, name, key_hash, created_at FROM api_keys WHERE key_hash = ? LIMIT 1`, keyHash).
		Scan(&k.ID, &k.Name, &k.KeyHash, &k.CreatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &k, nil
}

// ─── series registry (ADR 0002/0003) ────────────────────────────────────────

type Series struct {
	SeriesKey  string    `json:"series_key"`
	MetricName string    `json:"metric_name"`
	Tags       string    `json:"tags"` // JSON text
	Type       string    `json:"type"`
	FirstSeen  time.Time `json:"first_seen"`
	LastSeen   time.Time `json:"last_seen"`
}

// UpsertSeries は初出時に登録、既出なら last_seen を更新する。
func (s *Store) UpsertSeries(ctx context.Context, key, metric, tagsJSON, typ string) error {
	_, err := s.DB.ExecContext(ctx,
		`INSERT INTO series (series_key, metric_name, tags, type)
		 VALUES (?, ?, CAST(? AS JSON), ?)
		 ON DUPLICATE KEY UPDATE last_seen = CURRENT_TIMESTAMP(6)`,
		key, metric, tagsJSON, typ)
	return err
}

func (s *Store) CountSeries(ctx context.Context) (int, error) {
	var n int
	err := s.DB.QueryRowContext(ctx, `SELECT COUNT(*) FROM series`).Scan(&n)
	return n, err
}

func (s *Store) ListSeries(ctx context.Context, metric string) ([]Series, error) {
	q := `SELECT series_key, metric_name, tags, type, first_seen, last_seen FROM series`
	args := []any{}
	if metric != "" {
		q += ` WHERE metric_name = ?`
		args = append(args, metric)
	}
	q += ` ORDER BY metric_name, series_key`
	rows, err := s.DB.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Series
	for rows.Next() {
		var se Series
		if err := rows.Scan(&se.SeriesKey, &se.MetricName, &se.Tags, &se.Type, &se.FirstSeen, &se.LastSeen); err != nil {
			return nil, err
		}
		out = append(out, se)
	}
	return out, rows.Err()
}

// ─── rollups (ADR 0003) ─────────────────────────────────────────────────────

type Rollup struct {
	SeriesKey   string    `json:"series_key"`
	BucketTS    time.Time `json:"bucket_ts"`
	ResolutionS int       `json:"resolution_s"`
	Count       int64     `json:"count"`
	Sum         float64   `json:"sum"`
	Min         float64   `json:"min"`
	Max         float64   `json:"max"`
	Last        float64   `json:"last"`
	Hist        *string   `json:"hist,omitempty"`
}

// UpsertRollup は完了バケットを書き込む。aggregator は in-memory で集約済みの「完全な」
// バケットを渡すので、二重 flush は同値での上書き = 冪等 (ADR 0003)。
func (s *Store) UpsertRollup(ctx context.Context, r Rollup) error {
	_, err := s.DB.ExecContext(ctx,
		`INSERT INTO rollups (series_key, bucket_ts, resolution_s, cnt, sum_val, min_val, max_val, last_val, hist)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
		 ON DUPLICATE KEY UPDATE
		   cnt = VALUES(cnt), sum_val = VALUES(sum_val), min_val = VALUES(min_val),
		   max_val = VALUES(max_val), last_val = VALUES(last_val), hist = VALUES(hist)`,
		r.SeriesKey, r.BucketTS.UTC(), r.ResolutionS, r.Count, r.Sum, r.Min, r.Max, r.Last, r.Hist)
	return err
}

// QueryRollups は series_key 群の [from, to) を bucket_ts 昇順で返す。
func (s *Store) QueryRollups(ctx context.Context, seriesKey string, from, to time.Time, resolution int) ([]Rollup, error) {
	rows, err := s.DB.QueryContext(ctx,
		`SELECT series_key, bucket_ts, resolution_s, cnt, sum_val, min_val, max_val, last_val, hist
		   FROM rollups
		  WHERE series_key = ? AND resolution_s = ? AND bucket_ts >= ? AND bucket_ts < ?
		  ORDER BY bucket_ts`,
		seriesKey, resolution, from.UTC(), to.UTC())
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Rollup
	for rows.Next() {
		var r Rollup
		if err := rows.Scan(&r.SeriesKey, &r.BucketTS, &r.ResolutionS, &r.Count, &r.Sum, &r.Min, &r.Max, &r.Last, &r.Hist); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// DeleteRollupsBefore は retention 超のバケットを削除する (ADR 0003)。
func (s *Store) DeleteRollupsBefore(ctx context.Context, cutoff time.Time) (int64, error) {
	res, err := s.DB.ExecContext(ctx, `DELETE FROM rollups WHERE bucket_ts < ?`, cutoff.UTC())
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

// ─── alert rules / events (ADR 0004) ────────────────────────────────────────

type AlertRule struct {
	ID          int64   `json:"id"`
	OwnerID     int64   `json:"owner_id"`
	Name        string  `json:"name"`
	MetricName  string  `json:"metric_name"`
	TagMatchers string  `json:"tag_matchers"` // JSON text
	Comparator  string  `json:"comparator"`   // gt/lt
	Threshold   float64 `json:"threshold"`
	WindowS     int     `json:"window_s"`
	ForS        int     `json:"for_s"`
	Agg         string  `json:"agg"`
	Dynamic     bool    `json:"dynamic"`
	Enabled     bool    `json:"enabled"`
}

func (s *Store) CreateAlertRule(ctx context.Context, r AlertRule) (int64, error) {
	res, err := s.DB.ExecContext(ctx,
		`INSERT INTO alert_rules
		   (owner_id, name, metric_name, tag_matchers, comparator, threshold, window_s, for_s, agg, dynamic, enabled)
		 VALUES (?, ?, ?, CAST(? AS JSON), ?, ?, ?, ?, ?, ?, ?)`,
		r.OwnerID, r.Name, r.MetricName, r.TagMatchers, r.Comparator, r.Threshold,
		r.WindowS, r.ForS, r.Agg, r.Dynamic, r.Enabled)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

func (s *Store) EnabledAlertRules(ctx context.Context) ([]AlertRule, error) {
	return s.queryRules(ctx, `WHERE enabled = 1`)
}

func (s *Store) ListAlertRules(ctx context.Context) ([]AlertRule, error) {
	return s.queryRules(ctx, ``)
}

func (s *Store) queryRules(ctx context.Context, where string) ([]AlertRule, error) {
	rows, err := s.DB.QueryContext(ctx,
		`SELECT id, owner_id, name, metric_name, tag_matchers, comparator, threshold, window_s, for_s, agg, dynamic, enabled
		   FROM alert_rules `+where+` ORDER BY id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []AlertRule
	for rows.Next() {
		var r AlertRule
		if err := rows.Scan(&r.ID, &r.OwnerID, &r.Name, &r.MetricName, &r.TagMatchers, &r.Comparator,
			&r.Threshold, &r.WindowS, &r.ForS, &r.Agg, &r.Dynamic, &r.Enabled); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

type AlertEvent struct {
	ID        int64     `json:"id"`
	RuleID    int64     `json:"rule_id"`
	State     string    `json:"state"`
	Value     float64   `json:"value"`
	CreatedAt time.Time `json:"created_at"`
}

func (s *Store) InsertAlertEvent(ctx context.Context, ruleID int64, state string, value float64) error {
	_, err := s.DB.ExecContext(ctx,
		`INSERT INTO alert_events (rule_id, state, value) VALUES (?, ?, ?)`, ruleID, state, value)
	return err
}

// RecentAlertEvents は最新 limit 件の alert イベントを返す (新しい順)。
func (s *Store) RecentAlertEvents(ctx context.Context, limit int) ([]AlertEvent, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	rows, err := s.DB.QueryContext(ctx,
		`SELECT id, rule_id, state, value, created_at FROM alert_events ORDER BY id DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []AlertEvent
	for rows.Next() {
		var e AlertEvent
		if err := rows.Scan(&e.ID, &e.RuleID, &e.State, &e.Value, &e.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// LatestAlertState は rule の最新 state を返す。未発火なら ("ok", nil)。
func (s *Store) LatestAlertState(ctx context.Context, ruleID int64) (string, error) {
	var state string
	err := s.DB.QueryRowContext(ctx,
		`SELECT state FROM alert_events WHERE rule_id = ? ORDER BY id DESC LIMIT 1`, ruleID).Scan(&state)
	if errors.Is(err, sql.ErrNoRows) {
		return "ok", nil
	}
	if err != nil {
		return "", err
	}
	return state, nil
}
