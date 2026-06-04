// Package alert は周期評価の alert rule engine (ADR 0004)。
// eval loop goroutine が rollup を窓ごと評価し ok→pending→firing→ok の state machine を駆動、
// 状態遷移を append-only alert_events に記録する。
package alert

import (
	"context"
	"encoding/json"
	"log/slog"
	"time"

	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/store"
)

const (
	PhaseOK      = "ok"
	PhasePending = "pending"
	PhaseFiring  = "firing"
)

// AnomalyClient は dynamic rule の動的閾値を返す (ai-worker)。失敗時 ok=false で degrade。
type AnomalyClient interface {
	DynamicThreshold(ctx context.Context, points []float64) (float64, bool)
}

type ruleState struct {
	phase string
	since time.Time
}

type Engine struct {
	store     *store.Store
	ai        AnomalyClient // nil 可 (dynamic 無効 / 常に静的閾値)
	windowSec int
	every     time.Duration
	log       *slog.Logger

	states map[int64]ruleState // eval goroutine 専有 (single-owner)
}

func NewEngine(st *store.Store, ai AnomalyClient, windowSec, evalEverySec int, log *slog.Logger) *Engine {
	return &Engine{
		store:     st,
		ai:        ai,
		windowSec: windowSec,
		every:     time.Duration(evalEverySec) * time.Second,
		log:       log,
		states:    make(map[int64]ruleState),
	}
}

func (e *Engine) Run(ctx context.Context) {
	if e.every <= 0 {
		e.every = 10 * time.Second
	}
	t := time.NewTicker(e.every)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			e.EvaluateOnce(ctx, time.Now())
		}
	}
}

// EvaluateOnce は 1 評価パス。テストから now を制御して呼べる (single goroutine 前提)。
func (e *Engine) EvaluateOnce(ctx context.Context, now time.Time) {
	rules, err := e.store.EnabledAlertRules(ctx)
	if err != nil {
		if e.log != nil {
			e.log.Error("alert: list rules", slog.Any("err", err))
		}
		return
	}
	for _, rule := range rules {
		value, ok := e.evalRule(ctx, rule, now)
		if !ok {
			continue // データ無し → 状態を変えない
		}
		threshold := rule.Threshold
		if rule.Dynamic && e.ai != nil {
			if t, ok := e.ai.DynamicThreshold(ctx, []float64{value}); ok {
				threshold = t // ai-worker 不通なら静的閾値で継続 (degrade)
			}
		}
		breached := breach(rule.Comparator, value, threshold)

		st := e.states[rule.ID]
		if st.phase == "" {
			st.phase = PhaseOK
		}
		next, since, event := step(st.phase, st.since, now, breached, rule.ForS)
		e.states[rule.ID] = ruleState{phase: next, since: since}
		if event != "" {
			if err := e.store.InsertAlertEvent(ctx, rule.ID, event, value); err != nil && e.log != nil {
				e.log.Error("alert: insert event", slog.Any("err", err))
			}
		}
	}
}

// step は state machine の純粋ロジック (ADR 0004)。記録すべき event 名 (空=記録なし) を返す。
// 遷移: ok→pending(pending) / pending→firing(firing, for 経過) / firing→ok(resolved) / pending→ok(silent)。
// for_s==0 のときは ok→firing(firing) で即発火する。
func step(cur string, since, now time.Time, breached bool, forS int) (next string, sinceOut time.Time, event string) {
	if breached {
		switch cur {
		case PhaseFiring:
			return PhaseFiring, since, ""
		case PhasePending:
			if now.Sub(since) >= time.Duration(forS)*time.Second {
				return PhaseFiring, since, PhaseFiring
			}
			return PhasePending, since, ""
		default: // ok
			if forS <= 0 {
				return PhaseFiring, now, PhaseFiring
			}
			return PhasePending, now, PhasePending
		}
	}
	switch cur {
	case PhaseFiring:
		return PhaseOK, now, "resolved"
	case PhasePending:
		return PhaseOK, now, "" // 一度も発火せず解消 → silent
	default:
		return PhaseOK, since, ""
	}
}

func breach(comparator string, value, threshold float64) bool {
	switch comparator {
	case "lt":
		return value < threshold
	default: // gt
		return value > threshold
	}
}

// evalRule は rule にマッチする series の直近窓 rollup を集約し、comparator に応じた代表値を返す
// (gt なら最大 series 値 / lt なら最小 series 値 = 「どれか1つでも breach」型)。
func (e *Engine) evalRule(ctx context.Context, rule store.AlertRule, now time.Time) (float64, bool) {
	matchers := parseTags(rule.TagMatchers)
	series, err := e.store.ListSeries(ctx, rule.MetricName)
	if err != nil {
		return 0, false
	}
	from := now.Add(-time.Duration(rule.WindowS) * time.Second)
	var vals []float64
	for _, s := range series {
		if !tagsMatch(matchers, s.Tags) {
			continue
		}
		rollups, err := e.store.QueryRollups(ctx, s.SeriesKey, from, now, e.windowSec)
		if err != nil || len(rollups) == 0 {
			continue
		}
		vals = append(vals, aggregate(rollups, rule.Agg))
	}
	if len(vals) == 0 {
		return 0, false
	}
	if rule.Comparator == "lt" {
		return minF(vals), true
	}
	return maxF(vals), true
}

// aggregate は窓内 rollup を 1 スカラに畳む。
func aggregate(rs []store.Rollup, agg string) float64 {
	switch agg {
	case "sum":
		var s float64
		for _, r := range rs {
			s += r.Sum
		}
		return s
	case "max":
		m := rs[0].Max
		for _, r := range rs {
			if r.Max > m {
				m = r.Max
			}
		}
		return m
	case "min":
		m := rs[0].Min
		for _, r := range rs {
			if r.Min < m {
				m = r.Min
			}
		}
		return m
	case "last":
		return rs[len(rs)-1].Last
	default: // avg = Σsum / Σcount
		var sum float64
		var cnt int64
		for _, r := range rs {
			sum += r.Sum
			cnt += r.Count
		}
		if cnt == 0 {
			return 0
		}
		return sum / float64(cnt)
	}
}

func parseTags(jsonStr string) map[string]string {
	m := map[string]string{}
	if jsonStr == "" {
		return m
	}
	_ = json.Unmarshal([]byte(jsonStr), &m)
	return m
}

// tagsMatch は matchers が series tags の部分集合か (rule の tag 条件をすべて満たすか)。
func tagsMatch(matchers map[string]string, seriesTagsJSON string) bool {
	if len(matchers) == 0 {
		return true
	}
	st := parseTags(seriesTagsJSON)
	for k, v := range matchers {
		if st[k] != v {
			return false
		}
	}
	return true
}

func maxF(v []float64) float64 {
	m := v[0]
	for _, x := range v {
		if x > m {
			m = x
		}
	}
	return m
}

func minF(v []float64) float64 {
	m := v[0]
	for _, x := range v {
		if x < m {
			m = x
		}
	}
	return m
}
