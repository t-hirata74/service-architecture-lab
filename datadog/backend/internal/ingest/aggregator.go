package ingest

import (
	"context"
	"encoding/json"
	"time"

	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/store"
)

// bucket は 1 series の 1 時間窓の集約値 (ADR 0001)。
type bucket struct {
	count int64
	sum   float64
	min   float64
	max   float64
	last  float64
}

type seriesAgg struct {
	metric  string
	tags    string // JSON (encoding/json は map key をソートするので決定的)
	typ     string
	buckets map[int64]*bucket // window-start unix → bucket
}

// Aggregator は series→時間窓 ring buffer を専有する (ADR 0001)。
// メソッドは goroutine-safe ではない: Pipeline の単一 goroutine だけが Add/FlushCompleted を呼ぶ
// (discord Hub と同じ single-owner CSP)。テストは 1 goroutine から直接呼べる。
type Aggregator struct {
	sink      RollupSink
	c         *Counters
	windowSec int
	maxSeries int
	series    map[string]*seriesAgg
}

func NewAggregator(sink RollupSink, c *Counters, windowSec, maxSeries int) *Aggregator {
	return &Aggregator{
		sink:      sink,
		c:         c,
		windowSec: windowSec,
		maxSeries: maxSeries,
		series:    make(map[string]*seriesAgg),
	}
}

// Add は 1 サンプルを該当バケットに集約する。新規 series が cardinality 上限超なら drop (ADR 0002)。
func (a *Aggregator) Add(ks keyedSample) {
	sa, ok := a.series[ks.Key]
	if !ok {
		if len(a.series) >= a.maxSeries {
			a.c.DroppedCardinality.Add(1)
			return
		}
		tagsJSON, _ := json.Marshal(ks.Tags)
		sa = &seriesAgg{metric: ks.Name, tags: string(tagsJSON), typ: ks.Type, buckets: make(map[int64]*bucket)}
		a.series[ks.Key] = sa
		a.c.ActiveSeries.Store(int64(len(a.series)))
	}

	w := int64(a.windowSec)
	bstart := (ks.TS.Unix() / w) * w
	b, ok := sa.buckets[bstart]
	if !ok {
		b = &bucket{min: ks.Value, max: ks.Value}
		sa.buckets[bstart] = b
	}
	b.count++
	b.sum += ks.Value
	b.last = ks.Value
	if ks.Value < b.min {
		b.min = ks.Value
	}
	if ks.Value > b.max {
		b.max = ks.Value
	}
}

// FlushCompleted は「現在窓より過去で完了した」バケットを sink に upsert し ring から落とす。
// flush 失敗時はバケットを保持して次回再試行 (UNIQUE による冪等 upsert、ADR 0003)。
func (a *Aggregator) FlushCompleted(ctx context.Context, now time.Time) {
	w := int64(a.windowSec)
	for key, sa := range a.series {
		for bstart, b := range sa.buckets {
			if bstart+w > now.Unix() {
				continue // まだ窓が閉じていない (in-progress)
			}
			_ = a.sink.UpsertSeries(ctx, key, sa.metric, sa.tags, sa.typ)
			r := store.Rollup{
				SeriesKey: key, BucketTS: time.Unix(bstart, 0).UTC(), ResolutionS: a.windowSec,
				Count: b.count, Sum: b.sum, Min: b.min, Max: b.max, Last: b.last,
			}
			if err := a.sink.UpsertRollup(ctx, r); err != nil {
				a.c.FlushErrors.Add(1)
				continue // バケット保持 → 次 tick で再試行
			}
			delete(sa.buckets, bstart)
		}
	}
}
