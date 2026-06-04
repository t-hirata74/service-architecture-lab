package ingest

import (
	"context"
	"fmt"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/store"
)

// ADR 0002: ingestChan 満杯で Enqueue は drop して計測する (load shedding)。決定的に検証。
func TestEnqueueShedsWhenFull(t *testing.T) {
	p := NewPipeline(&fakeSink{}, Options{
		IngestBuffer: 2, SampleBuffer: 2, Workers: 1, WindowSec: 10, MaxSeries: 100,
	})
	// Run せず (consumer なし) → ingestChan(cap 2) に 2 件入り、残り 3 件は drop。
	accepted := 0
	for i := 0; i < 5; i++ {
		if p.Enqueue(Sample{Name: "cpu", Value: 1, TS: time.Unix(100, 0)}) {
			accepted++
		}
	}
	if accepted != 2 {
		t.Fatalf("accepted = %d, want 2 (buffer cap)", accepted)
	}
	if got := p.Counters.DroppedIngest.Load(); got != 3 {
		t.Fatalf("DroppedIngest = %d, want 3", got)
	}
}

// 複数 producer が同時に Enqueue し、worker pool + 単一 aggregator が捌く間、
// counters / series map に race が無いことを go test -race で確認する (discord/uber の race spec 相当)。
func TestConcurrentIngestNoRace(t *testing.T) {
	p := NewPipeline(&fakeSink{}, Options{
		IngestBuffer: 64, SampleBuffer: 64, Workers: 4, WindowSec: 1, MaxSeries: 50,
	})

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { p.Run(ctx); close(done) }()

	var wg sync.WaitGroup
	for g := 0; g < 4; g++ {
		wg.Add(1)
		go func(g int) {
			defer wg.Done()
			for i := 0; i < 500; i++ {
				p.Enqueue(Sample{
					Name:  fmt.Sprintf("m%d", (g*500+i)%80), // 80 distinct → cap 50 で一部 cardinality drop
					Value: float64(i),
					TS:    time.Unix(int64(100+i%3), 0),
				})
			}
		}(g)
	}
	wg.Wait()
	time.Sleep(50 * time.Millisecond) // 残りを drain させる
	cancel()

	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("pipeline did not stop (deadlock?)")
	}

	s := p.Counters.Snapshot()
	if s.ActiveSeries > 50 {
		t.Fatalf("ActiveSeries = %d, exceeds MaxSeries 50", s.ActiveSeries)
	}
	t.Logf("stats: %+v", s)
}

// live な async パス: Enqueue → worker → 実 aggregator goroutine → flush → 実 store → query。
// store.Store を sink にして Run() の本物の flush tick を通す (DATADOG_TEST_DB 必須)。
func TestPipelineFlushesToStoreLive(t *testing.T) {
	dsn := os.Getenv("DATADOG_TEST_DB")
	if dsn == "" {
		t.Skip("set DATADOG_TEST_DB to run live pipeline test")
	}
	st, err := store.Open(dsn)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	for _, tbl := range []string{"rollups", "series"} {
		st.DB.Exec("DELETE FROM " + tbl)
	}

	p := NewPipeline(st, Options{IngestBuffer: 64, SampleBuffer: 64, Workers: 2, WindowSec: 1, MaxSeries: 100})
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go p.Run(ctx)

	tags := map[string]string{"h": "a"}
	ts := time.Now().Add(-2 * time.Second) // 既に閉じた窓 → 次の flush tick で確定
	p.Enqueue(Sample{Name: "live.metric", Tags: tags, Type: "gauge", Value: 42, TS: ts})

	key := SeriesKey("live.metric", tags)
	var rows []store.Rollup
	for i := 0; i < 40; i++ {
		rows, _ = st.QueryRollups(ctx, key, ts.Add(-time.Minute), time.Now().Add(time.Minute), 1)
		if len(rows) > 0 {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}
	if len(rows) != 1 {
		t.Fatalf("flushed rollups = %d, want 1 (async pipeline → store)", len(rows))
	}
	if rows[0].Count != 1 || rows[0].Sum != 42 {
		t.Fatalf("rollup = %+v, want count1 sum42", rows[0])
	}
}
