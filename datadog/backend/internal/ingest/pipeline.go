package ingest

import (
	"context"
	"log/slog"
	"sync"
	"time"
)

// Pipeline は fan-in パイプライン全体を束ねる (ADR 0001/0002)。
//   Enqueue → ingestChan (bounded) → worker pool → sampleChan (bounded) → aggregator goroutine
// bounded chan が満杯なら non-blocking drop (load shedding)。
type Pipeline struct {
	Counters *Counters

	ingestChan chan Sample
	sampleChan chan keyedSample
	agg        *Aggregator
	workers    int
	flushEvery time.Duration
	log        *slog.Logger
}

type Options struct {
	IngestBuffer int
	SampleBuffer int
	Workers      int
	WindowSec    int
	MaxSeries    int
	Log          *slog.Logger
}

func NewPipeline(sink RollupSink, o Options) *Pipeline {
	c := &Counters{}
	return &Pipeline{
		Counters:   c,
		ingestChan: make(chan Sample, o.IngestBuffer),
		sampleChan: make(chan keyedSample, o.SampleBuffer),
		agg:        NewAggregator(sink, c, o.WindowSec, o.MaxSeries),
		workers:    o.Workers,
		flushEvery: time.Duration(o.WindowSec) * time.Second,
		log:        o.Log,
	}
}

// Enqueue は handler から呼ぶ。ingestChan 満杯なら drop して false (load shedding, ADR 0002)。
func (p *Pipeline) Enqueue(s Sample) bool {
	if s.TS.IsZero() {
		s.TS = time.Now()
	}
	select {
	case p.ingestChan <- s:
		return true
	default:
		p.Counters.DroppedIngest.Add(1)
		return false
	}
}

// Run は worker pool と aggregator goroutine を起動する。ctx 終了で停止 + 最終 flush。
// aggregator goroutine が series map の単一所有者 (Add/FlushCompleted を呼ぶのはここだけ)。
func (p *Pipeline) Run(ctx context.Context) {
	var wg sync.WaitGroup
	for i := 0; i < p.workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			p.worker(ctx)
		}()
	}

	flushEvery := p.flushEvery
	if flushEvery <= 0 {
		flushEvery = time.Second
	}
	ticker := time.NewTicker(flushEvery)
	defer ticker.Stop()

	for {
		select {
		case ks := <-p.sampleChan:
			p.agg.Add(ks)
		case <-ticker.C:
			p.agg.FlushCompleted(ctx, time.Now())
		case <-ctx.Done():
			wg.Wait() // worker を止めてから最終 flush (sampleChan への送信が終わる)
			drainAndFlush(p)
			return
		}
	}
}

// drainAndFlush は停止時に sampleChan の残りを取り込み、現在窓も強制的に完了扱いで flush する。
func drainAndFlush(p *Pipeline) {
	for {
		select {
		case ks := <-p.sampleChan:
			p.agg.Add(ks)
		default:
			// 現在窓も含めて全バケットを flush するため now を 1 窓先に進める
			p.agg.FlushCompleted(context.Background(), time.Now().Add(p.flushEvery))
			return
		}
	}
}

func (p *Pipeline) worker(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case s := <-p.ingestChan:
			ks := keyedSample{Key: SeriesKey(s.Name, s.Tags), Sample: s}
			select {
			case p.sampleChan <- ks:
			default:
				p.Counters.DroppedIngest.Add(1) // sampleChan 満杯 → drop
			}
		}
	}
}
