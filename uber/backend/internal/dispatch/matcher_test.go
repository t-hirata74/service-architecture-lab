package dispatch

import (
	"context"
	"sync/atomic"
	"testing"
	"time"

	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/geo"
)

// fakeAcceptor は AcceptTrip 呼び出しを記録 + 任意で「勝った/負けた」を返す。
type fakeAcceptor struct {
	calls atomic.Int32
	wins  bool
}

func (f *fakeAcceptor) AcceptTrip(_ context.Context, _, _ int64) (bool, error) {
	f.calls.Add(1)
	return f.wins, nil
}

// 1 driver / 1 trip の正常系。matcher が offer を送り、accept 応答を受け、AcceptTrip が 1 回呼ばれる。
func TestMatcher_SingleHappyPath(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	acc := &fakeAcceptor{wins: true}
	cfg := MatcherConfig{
		OfferTimeout:    200 * time.Millisecond,
		InitialKRing:    0,
		ExpandedKRing:   0,
		OverallDeadline: 1 * time.Second,
	}
	m := NewMatcher(geo.Cell("8a2a1072b59ffff"), cfg, nil, acc)
	go m.Run(ctx)

	driverOfferCh := make(chan Offer, 1)
	m.NotifyPosition(PositionUpdate{
		DriverUserID: 42,
		Cell:         m.cell,
		Lat:          35.6812, Lng: 139.7671,
		Online:  true,
		OfferCh: driverOfferCh,
	})
	// position update が反映されるまで少し待つ
	time.Sleep(50 * time.Millisecond)

	m.EnqueueRequest(TripRequest{
		TripID:     100,
		PickupCell: m.cell,
		PickupLat:  35.6812, PickupLng: 139.7671,
		DropoffLat: 35.6896, DropoffLng: 139.7006,
	})

	// driver の WS goroutine 役: offer を受け、accept で返す
	select {
	case offer := <-driverOfferCh:
		if offer.TripID != 100 {
			t.Fatalf("expected offer for trip 100, got %d", offer.TripID)
		}
		m.HandleOfferResponse(OfferResponse{TripID: 100, DriverUserID: 42, Accepted: true})
	case <-time.After(500 * time.Millisecond):
		t.Fatal("driver did not receive offer in 500ms")
	}

	// AcceptTrip が 1 回以上呼ばれるまで待つ (handleRequest が同期的に終わるまで)
	deadline := time.Now().Add(500 * time.Millisecond)
	for time.Now().Before(deadline) {
		if acc.calls.Load() >= 1 {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if got := acc.calls.Load(); got != 1 {
		t.Errorf("AcceptTrip call count = %d, want 1", got)
	}
}

// 同 cell に 2 driver、trip が 1 件: 最初の候補が reject、次の候補が accept、AcceptTrip が 2 回呼ばれる
// (1 回目は reject なので呼ばれないが、accept 後の 1 回だけ)。
//
// 簡単のため reject ではなく timeout で次へ進むパスを検証する。
func TestMatcher_TimeoutThenNext(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	acc := &fakeAcceptor{wins: true}
	cfg := MatcherConfig{
		OfferTimeout:    100 * time.Millisecond, // 短い
		InitialKRing:    0,
		ExpandedKRing:   0,
		OverallDeadline: 2 * time.Second,
	}
	m := NewMatcher(geo.Cell("8a2a1072b59ffff"), cfg, nil, acc)
	go m.Run(ctx)

	// 2 driver を登録。1 人目 (no response) はタイムアウトさせ、2 人目だけ accept で返す。
	silentCh := make(chan Offer, 1)
	respondingCh := make(chan Offer, 1)
	m.NotifyPosition(PositionUpdate{DriverUserID: 1, Cell: m.cell, Online: true, OfferCh: silentCh})
	m.NotifyPosition(PositionUpdate{DriverUserID: 2, Cell: m.cell, Online: true, OfferCh: respondingCh})
	time.Sleep(50 * time.Millisecond)

	m.EnqueueRequest(TripRequest{TripID: 200, PickupCell: m.cell})

	// どちらかが offer を受ける。受けた方が「silent」なら何もしない、「responding」なら accept で返す。
	// matcher は順序保証しないので、最初に offer を受けた driver で判定する。
	go func() {
		for {
			select {
			case <-silentCh:
				// silent: 何もしない (timeout 発火を待つ)
			case <-respondingCh:
				m.HandleOfferResponse(OfferResponse{TripID: 200, DriverUserID: 2, Accepted: true})
			case <-time.After(1 * time.Second):
				return
			}
		}
	}()

	// AcceptTrip が 1 回以上呼ばれることを assertion (responding 側で勝つ)
	deadline := time.Now().Add(800 * time.Millisecond)
	for time.Now().Before(deadline) {
		if acc.calls.Load() >= 1 {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Errorf("AcceptTrip never called within 800ms; calls=%d", acc.calls.Load())
}

// non-blocking send + drop: driver chan が満杯なら offer は drop し、AcceptTrip は呼ばれない
// (本テストは driver 1 人の場合、matcher は overall deadline まで再試行しないので
// 単に「無事に終了する」ことを確認する程度に留める)。
func TestMatcher_NoCandidate(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	acc := &fakeAcceptor{wins: true}
	cfg := MatcherConfig{
		OfferTimeout:    50 * time.Millisecond,
		InitialKRing:    0,
		ExpandedKRing:   0,
		OverallDeadline: 200 * time.Millisecond,
	}
	m := NewMatcher(geo.Cell("8a2a1072b59ffff"), cfg, nil, acc)
	go m.Run(ctx)

	// driver 登録せずに request 投入
	m.EnqueueRequest(TripRequest{TripID: 300, PickupCell: m.cell})

	// OverallDeadline 経過後も AcceptTrip は 0 回
	time.Sleep(300 * time.Millisecond)
	if got := acc.calls.Load(); got != 0 {
		t.Errorf("AcceptTrip should not be called when no candidates, got %d calls", got)
	}
}

// CellRegistry の lazy create と Len 確認
func TestCellRegistry_LazyCreate(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	r := NewCellRegistry(ctx, DefaultMatcherConfig(), nil, &fakeAcceptor{})
	if r.Len() != 0 {
		t.Errorf("initial Len = %d, want 0", r.Len())
	}

	c1 := geo.Cell("8a2a1072b59ffff")
	c2 := geo.Cell("8a2a1072b597fff")

	m1 := r.GetOrCreate(c1)
	if r.Len() != 1 {
		t.Errorf("after 1 cell Len = %d, want 1", r.Len())
	}
	m1b := r.GetOrCreate(c1)
	if m1 != m1b {
		t.Error("GetOrCreate(c1) should return same instance on second call")
	}
	if r.Len() != 1 {
		t.Errorf("after 1 cell twice Len = %d, want 1", r.Len())
	}

	r.GetOrCreate(c2)
	if r.Len() != 2 {
		t.Errorf("after 2 cells Len = %d, want 2", r.Len())
	}
}
