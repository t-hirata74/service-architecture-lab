package ingest

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/store"
)

type fakeSink struct {
	mu       sync.Mutex
	rollups  []store.Rollup
	failNext bool
}

func (f *fakeSink) UpsertSeries(_ context.Context, _, _, _, _ string) error { return nil }

func (f *fakeSink) UpsertRollup(_ context.Context, r store.Rollup) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.failNext {
		return errors.New("boom")
	}
	f.rollups = append(f.rollups, r)
	return nil
}

func (f *fakeSink) count() int { f.mu.Lock(); defer f.mu.Unlock(); return len(f.rollups) }

func add(a *Aggregator, name string, tags map[string]string, v float64, ts time.Time) {
	a.Add(keyedSample{Key: SeriesKey(name, tags), Sample: Sample{Name: name, Tags: tags, Type: "gauge", Value: v, TS: ts}})
}

func TestAggregatesWithinWindow(t *testing.T) {
	sink := &fakeSink{}
	a := NewAggregator(sink, &Counters{}, 10, 100)
	tags := map[string]string{"host": "a"}

	add(a, "cpu", tags, 10, time.Unix(100, 0))
	add(a, "cpu", tags, 20, time.Unix(103, 0))
	add(a, "cpu", tags, 5, time.Unix(109, 0))

	a.FlushCompleted(context.Background(), time.Unix(115, 0)) // 窓 [100,110) は閉じている

	if sink.count() != 1 {
		t.Fatalf("rollups = %d, want 1", sink.count())
	}
	r := sink.rollups[0]
	if r.Count != 3 || r.Sum != 35 || r.Min != 5 || r.Max != 20 || r.Last != 5 {
		t.Fatalf("rollup = %+v, want count3 sum35 min5 max20 last5", r)
	}
	if r.BucketTS != time.Unix(100, 0).UTC() || r.ResolutionS != 10 {
		t.Fatalf("bucket = %v res %d, want Unix(100)/10", r.BucketTS, r.ResolutionS)
	}
}

func TestBucketsSplitByWindow(t *testing.T) {
	sink := &fakeSink{}
	a := NewAggregator(sink, &Counters{}, 10, 100)
	add(a, "cpu", nil, 1, time.Unix(100, 0)) // 窓 100
	add(a, "cpu", nil, 2, time.Unix(112, 0)) // 窓 110

	a.FlushCompleted(context.Background(), time.Unix(125, 0))
	if sink.count() != 2 {
		t.Fatalf("rollups = %d, want 2 (2 windows)", sink.count())
	}
}

func TestNotFlushedWhileWindowOpen(t *testing.T) {
	sink := &fakeSink{}
	a := NewAggregator(sink, &Counters{}, 10, 100)
	add(a, "cpu", nil, 1, time.Unix(100, 0))

	a.FlushCompleted(context.Background(), time.Unix(105, 0)) // 窓 [100,110) はまだ開いている
	if sink.count() != 0 {
		t.Fatalf("rollups = %d, want 0 (window open)", sink.count())
	}
	a.FlushCompleted(context.Background(), time.Unix(115, 0)) // 閉じた
	if sink.count() != 1 {
		t.Fatalf("rollups = %d, want 1 after close", sink.count())
	}
}

// ADR 0002: series 上限超過で新規 series を drop し計測する。
func TestCardinalityCap(t *testing.T) {
	c := &Counters{}
	a := NewAggregator(&fakeSink{}, c, 10, 2)
	add(a, "m1", nil, 1, time.Unix(100, 0))
	add(a, "m2", nil, 1, time.Unix(100, 0))
	add(a, "m3", nil, 1, time.Unix(100, 0)) // 上限超 → drop

	if got := c.DroppedCardinality.Load(); got != 1 {
		t.Fatalf("DroppedCardinality = %d, want 1", got)
	}
	if got := c.ActiveSeries.Load(); got != 2 {
		t.Fatalf("ActiveSeries = %d, want 2", got)
	}
}

// ADR 0003: flush 失敗時はバケットを保持し、次回 flush で再試行できる (冪等 upsert 前提)。
func TestFlushErrorKeepsBucket(t *testing.T) {
	sink := &fakeSink{failNext: true}
	c := &Counters{}
	a := NewAggregator(sink, c, 10, 100)
	add(a, "cpu", nil, 7, time.Unix(100, 0))

	a.FlushCompleted(context.Background(), time.Unix(115, 0)) // 失敗
	if c.FlushErrors.Load() != 1 || sink.count() != 0 {
		t.Fatalf("after fail: errors=%d rollups=%d, want 1/0", c.FlushErrors.Load(), sink.count())
	}

	sink.failNext = false
	a.FlushCompleted(context.Background(), time.Unix(115, 0)) // 再試行成功 (バケットが保持されていた)
	if sink.count() != 1 {
		t.Fatalf("after retry: rollups=%d, want 1 (bucket was kept)", sink.count())
	}
}
