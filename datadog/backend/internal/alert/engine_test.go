package alert

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/ingest"
	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/store"
)

// ─── 純粋 state machine (DB 不要) ─────────────────────────────────────────────

func TestStepImmediateFire(t *testing.T) {
	// for_s=0: ok → firing 即発火
	next, _, ev := step(PhaseOK, time.Time{}, time.Unix(100, 0), true, 0)
	if next != PhaseFiring || ev != PhaseFiring {
		t.Fatalf("ok+breached(for0) = %s/%q, want firing/firing", next, ev)
	}
	// firing 継続: event 無し
	if n, _, e := step(PhaseFiring, time.Unix(100, 0), time.Unix(110, 0), true, 0); n != PhaseFiring || e != "" {
		t.Fatalf("firing+breached = %s/%q, want firing/''", n, e)
	}
	// firing → ok: resolved
	if n, _, e := step(PhaseFiring, time.Unix(100, 0), time.Unix(120, 0), false, 0); n != PhaseOK || e != "resolved" {
		t.Fatalf("firing+!breached = %s/%q, want ok/resolved", n, e)
	}
}

func TestStepForDuration(t *testing.T) {
	t0 := time.Unix(1000, 0)
	// ok → pending (for=30)
	n, since, ev := step(PhaseOK, time.Time{}, t0, true, 30)
	if n != PhasePending || ev != PhasePending {
		t.Fatalf("ok+breached(for30) = %s/%q, want pending/pending", n, ev)
	}
	// pending 継続中 (10s < 30s): event 無し
	if n2, _, e := step(PhasePending, since, t0.Add(10*time.Second), true, 30); n2 != PhasePending || e != "" {
		t.Fatalf("pending@+10 = %s/%q, want pending/''", n2, e)
	}
	// for 経過 (40s >= 30s): firing
	if n3, _, e := step(PhasePending, since, t0.Add(40*time.Second), true, 30); n3 != PhaseFiring || e != PhaseFiring {
		t.Fatalf("pending@+40 = %s/%q, want firing/firing", n3, e)
	}
}

func TestStepPendingToOkSilent(t *testing.T) {
	// 一度も発火せず解消 → silent (event 無し)
	n, _, e := step(PhasePending, time.Unix(100, 0), time.Unix(105, 0), false, 30)
	if n != PhaseOK || e != "" {
		t.Fatalf("pending+!breached = %s/%q, want ok/'' (silent)", n, e)
	}
}

// ─── DB 統合 (DATADOG_TEST_DB) ───────────────────────────────────────────────

func openTest(t *testing.T) *store.Store {
	dsn := os.Getenv("DATADOG_TEST_DB")
	if dsn == "" {
		t.Skip("set DATADOG_TEST_DB to run alert integration tests")
	}
	st, err := store.Open(dsn)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	ctx := context.Background()
	for _, tbl := range []string{"alert_events", "alert_rules", "rollups", "series", "users"} {
		st.DB.ExecContext(ctx, "DELETE FROM "+tbl)
	}
	return st
}

func seedBreachingMetric(t *testing.T, st *store.Store, avg float64, now time.Time) {
	ctx := context.Background()
	key := ingest.SeriesKey("cpu", map[string]string{"host": "a"})
	if err := st.UpsertSeries(ctx, key, "cpu", `{"host":"a"}`, "gauge"); err != nil {
		t.Fatalf("series: %v", err)
	}
	if err := st.UpsertRollup(ctx, store.Rollup{
		SeriesKey: key, BucketTS: now.Add(-15 * time.Second).UTC(), ResolutionS: 10,
		Count: 1, Sum: avg, Min: avg, Max: avg, Last: avg,
	}); err != nil {
		t.Fatalf("rollup: %v", err)
	}
}

func TestEvaluateFiresAndResolves(t *testing.T) {
	st := openTest(t)
	ctx := context.Background()
	now := time.Now()

	uid, _ := st.CreateUser(ctx, "o@example.com", "x")
	ruleID, err := st.CreateAlertRule(ctx, store.AlertRule{
		OwnerID: uid, Name: "cpu high", MetricName: "cpu", TagMatchers: "{}",
		Comparator: "gt", Threshold: 80, WindowS: 60, ForS: 0, Agg: "avg", Enabled: true,
	})
	if err != nil {
		t.Fatalf("create rule: %v", err)
	}

	e := NewEngine(st, nil, 10, 10, nil)

	// breach (avg=90 > 80, for=0) → firing
	seedBreachingMetric(t, st, 90, now)
	e.EvaluateOnce(ctx, now)
	if s, _ := st.LatestAlertState(ctx, ruleID); s != "firing" {
		t.Fatalf("state = %q, want firing", s)
	}

	// 解消 (avg を 10 に上書き = 同バケット冪等 upsert) → resolved
	seedBreachingMetric(t, st, 10, now)
	e.EvaluateOnce(ctx, now)
	if s, _ := st.LatestAlertState(ctx, ruleID); s != "resolved" {
		t.Fatalf("state = %q, want resolved", s)
	}
}

func TestEvaluateNoDataNoEvent(t *testing.T) {
	st := openTest(t)
	ctx := context.Background()
	uid, _ := st.CreateUser(ctx, "o2@example.com", "x")
	ruleID, _ := st.CreateAlertRule(ctx, store.AlertRule{
		OwnerID: uid, Name: "idle", MetricName: "absent.metric", TagMatchers: "{}",
		Comparator: "gt", Threshold: 1, WindowS: 60, ForS: 0, Agg: "avg", Enabled: true,
	})
	e := NewEngine(st, nil, 10, 10, nil)
	e.EvaluateOnce(ctx, time.Now()) // データ無し → 状態変化なし
	if s, _ := st.LatestAlertState(ctx, ruleID); s != "ok" {
		t.Fatalf("state = %q, want ok (no data)", s)
	}
}
