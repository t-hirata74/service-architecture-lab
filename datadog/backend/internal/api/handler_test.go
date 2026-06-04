package api_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/api"
	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/auth"
	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/config"
	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/ingest"
	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/store"
)

// DATADOG_TEST_DB が設定されているときだけ走る HTTP 層統合テスト。
func newTestHandler(t *testing.T) (*api.Handler, *store.Store) {
	dsn := os.Getenv("DATADOG_TEST_DB")
	if dsn == "" {
		t.Skip("set DATADOG_TEST_DB to run api integration tests")
	}
	st, err := store.Open(dsn)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	ctx := context.Background()
	for _, tbl := range []string{"alert_events", "alert_rules", "rollups", "series", "api_keys", "users"} {
		st.DB.ExecContext(ctx, "DELETE FROM "+tbl)
	}
	cfg := &config.Config{JWTSecret: "testsecret123", IngestAPIKey: "test-key", WindowSeconds: 10, MaxSeries: 100}
	pipe := ingest.NewPipeline(st, ingest.Options{IngestBuffer: 1024, SampleBuffer: 1024, Workers: 2, WindowSec: 10, MaxSeries: 100})
	return &api.Handler{Store: st, Cfg: cfg, Pipeline: pipe}, st
}

func do(h *api.Handler, method, path string, body any, headers map[string]string) *httptest.ResponseRecorder {
	var rdr *bytes.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rdr = bytes.NewReader(b)
	} else {
		rdr = bytes.NewReader(nil)
	}
	req := httptest.NewRequest(method, path, rdr)
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	h.Routes().ServeHTTP(rec, req)
	return rec
}

func TestIngestAuth(t *testing.T) {
	h, _ := newTestHandler(t)
	body := map[string]any{"samples": []map[string]any{{"name": "cpu", "value": 1}}}

	// API key 無し → 401
	if rec := do(h, "POST", "/ingest", body, nil); rec.Code != http.StatusUnauthorized {
		t.Fatalf("no key: code = %d, want 401", rec.Code)
	}
	// API key あり → 202
	rec := do(h, "POST", "/ingest", body, map[string]string{"X-API-Key": "test-key"})
	if rec.Code != http.StatusAccepted {
		t.Fatalf("with key: code = %d, want 202 (%s)", rec.Code, rec.Body.String())
	}
	var resp map[string]any
	json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp["accepted"].(float64) != 1 {
		t.Fatalf("accepted = %v, want 1", resp["accepted"])
	}
}

func TestQueryRequiresJWTAndReturnsRollups(t *testing.T) {
	h, st := newTestHandler(t)
	ctx := context.Background()

	// JWT 無し → 401
	if rec := do(h, "GET", "/query?metric=cpu", nil, nil); rec.Code != http.StatusUnauthorized {
		t.Fatalf("no jwt: code = %d, want 401", rec.Code)
	}

	// user + token
	uid, err := st.CreateUser(ctx, "u@example.com", "x")
	if err != nil {
		t.Fatalf("create user: %v", err)
	}
	tok, _ := auth.SignUserToken([]byte(h.Cfg.JWTSecret), uid, time.Hour)

	// series + rollup を事前投入 (pipeline の非同期 timing を避け query 層を決定的に検証)
	key := ingest.SeriesKey("cpu", map[string]string{"host": "a"})
	if err := st.UpsertSeries(ctx, key, "cpu", `{"host":"a"}`, "gauge"); err != nil {
		t.Fatalf("upsert series: %v", err)
	}
	if err := st.UpsertRollup(ctx, store.Rollup{
		SeriesKey: key, BucketTS: time.Now().Add(-30 * time.Second).UTC(), ResolutionS: 10,
		Count: 4, Sum: 40, Min: 5, Max: 15, Last: 12,
	}); err != nil {
		t.Fatalf("upsert rollup: %v", err)
	}

	rec := do(h, "GET", "/query?metric=cpu", nil, map[string]string{"Authorization": "Bearer " + tok})
	if rec.Code != http.StatusOK {
		t.Fatalf("query: code = %d, want 200 (%s)", rec.Code, rec.Body.String())
	}
	var resp struct {
		Series []struct {
			Points []struct {
				Count int     `json:"count"`
				Avg   float64 `json:"avg"`
			} `json:"points"`
		} `json:"series"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(resp.Series) != 1 || len(resp.Series[0].Points) != 1 {
		t.Fatalf("series/points = %d/%v, want 1/1", len(resp.Series), resp.Series)
	}
	if resp.Series[0].Points[0].Count != 4 || resp.Series[0].Points[0].Avg != 10 {
		t.Fatalf("point = %+v, want count4 avg10", resp.Series[0].Points[0])
	}
}
