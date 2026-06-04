// Package ingest は fan-in パイプライン (ADR 0001) を実装する:
//   handler → bounded ingest chan → worker pool (key 計算) → single-owner aggregator → flush rollup
// backpressure は bounded chan の non-blocking drop = load shedding (ADR 0002)。
package ingest

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"sort"
	"strings"
	"sync/atomic"
	"time"

	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/store"
)

// Sample は handler が decode した 1 メトリクスサンプル。
type Sample struct {
	Name  string            `json:"name"`
	Tags  map[string]string `json:"tags"`
	Type  string            `json:"type"` // counter / gauge / histogram
	Value float64           `json:"value"`
	TS    time.Time         `json:"ts"`
}

// keyedSample は worker が series key を付与したサンプル (aggregator へ fan-in)。
type keyedSample struct {
	Key string
	Sample
}

// RollupSink は aggregator の flush 先 (store.Store が満たす)。テストは fake を差し込める。
type RollupSink interface {
	UpsertSeries(ctx context.Context, key, metric, tagsJSON, typ string) error
	UpsertRollup(ctx context.Context, r store.Rollup) error
}

// Counters は全 goroutine から読み書きされるので atomic (ADR 0002 の自己メトリクス)。
type Counters struct {
	DroppedIngest      atomic.Int64 // chan 満杯による load shedding
	DroppedCardinality atomic.Int64 // series 上限超過による drop
	FlushErrors        atomic.Int64 // rollup flush 失敗 (バケットは保持し再試行)
	ActiveSeries       atomic.Int64 // 現在の series 数 (cardinality gauge)
}

type StatsSnapshot struct {
	DroppedIngest      int64 `json:"dropped_ingest"`
	DroppedCardinality int64 `json:"dropped_cardinality"`
	FlushErrors        int64 `json:"flush_errors"`
	ActiveSeries       int64 `json:"active_series"`
}

func (c *Counters) Snapshot() StatsSnapshot {
	return StatsSnapshot{
		DroppedIngest:      c.DroppedIngest.Load(),
		DroppedCardinality: c.DroppedCardinality.Load(),
		FlushErrors:        c.FlushErrors.Load(),
		ActiveSeries:       c.ActiveSeries.Load(),
	}
}

// SeriesKey は metric 名 + ソート済み tags から決定的な series 識別子 (sha256 hex) を作る。
// store.series.series_key と一致させる。
func SeriesKey(name string, tags map[string]string) string {
	keys := make([]string, 0, len(tags))
	for k := range tags {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var b strings.Builder
	b.WriteString(name)
	for _, k := range keys {
		b.WriteByte(0)
		b.WriteString(k)
		b.WriteByte('=')
		b.WriteString(tags[k])
	}
	sum := sha256.Sum256([]byte(b.String()))
	return hex.EncodeToString(sum[:])
}
