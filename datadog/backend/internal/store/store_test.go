package store_test

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/auth"
	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/store"
)

// DATADOG_TEST_DB (DSN) が設定されているときだけ走る統合テスト (uber の UBER_TEST_DB と同方針)。
// migration 適用済みの DB を要求する。
func openTest(t *testing.T) *store.Store {
	dsn := os.Getenv("DATADOG_TEST_DB")
	if dsn == "" {
		t.Skip("set DATADOG_TEST_DB to run store integration tests")
	}
	st, err := store.Open(dsn)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	ctx := context.Background()
	for _, tbl := range []string{"alert_events", "alert_rules", "rollups", "series", "api_keys", "users"} {
		if _, err := st.DB.ExecContext(ctx, "DELETE FROM "+tbl); err != nil {
			t.Fatalf("clean %s: %v", tbl, err)
		}
	}
	return st
}

func TestUsersAndAPIKeys(t *testing.T) {
	st := openTest(t)
	ctx := context.Background()

	id, err := st.CreateUser(ctx, "a@example.com", "hash")
	if err != nil {
		t.Fatalf("create user: %v", err)
	}
	u, err := st.UserByEmail(ctx, "a@example.com")
	if err != nil || u.ID != id {
		t.Fatalf("user by email: %v (%+v)", err, u)
	}
	if _, err := st.UserByEmail(ctx, "nope@example.com"); err != store.ErrNotFound {
		t.Fatalf("want ErrNotFound, got %v", err)
	}

	keyHash := auth.HashAPIKey("agent-key")
	if _, err := st.CreateAPIKey(ctx, "agent", keyHash); err != nil {
		t.Fatalf("create api key: %v", err)
	}
	if _, err := st.APIKeyByHash(ctx, keyHash); err != nil {
		t.Fatalf("api key by hash: %v", err)
	}
}

func TestSeriesUpsertIdempotent(t *testing.T) {
	st := openTest(t)
	ctx := context.Background()

	for i := 0; i < 3; i++ {
		if err := st.UpsertSeries(ctx, "sk1", "cpu.load", `{"host":"a"}`, "gauge"); err != nil {
			t.Fatalf("upsert series: %v", err)
		}
	}
	n, err := st.CountSeries(ctx)
	if err != nil || n != 1 {
		t.Fatalf("count series = %d (err %v), want 1 (idempotent)", n, err)
	}
}

// ADR 0003: 完了バケットの二重 flush は同値での上書き = 冪等 (count/sum を二重計上しない)。
func TestRollupUpsertIdempotent(t *testing.T) {
	st := openTest(t)
	ctx := context.Background()

	r := store.Rollup{
		SeriesKey: "sk1", BucketTS: time.Unix(100, 0).UTC(), ResolutionS: 10,
		Count: 5, Sum: 50, Min: 1, Max: 20, Last: 9,
	}
	for i := 0; i < 2; i++ { // 二重 flush
		if err := st.UpsertRollup(ctx, r); err != nil {
			t.Fatalf("upsert rollup: %v", err)
		}
	}
	rows, err := st.QueryRollups(ctx, "sk1", time.Unix(0, 0), time.Unix(1000, 0), 10)
	if err != nil {
		t.Fatalf("query rollups: %v", err)
	}
	if len(rows) != 1 {
		t.Fatalf("rollup rows = %d, want 1 (idempotent upsert)", len(rows))
	}
	if rows[0].Count != 5 || rows[0].Sum != 50 {
		t.Fatalf("rollup doubled: count=%d sum=%v, want 5/50", rows[0].Count, rows[0].Sum)
	}
}
