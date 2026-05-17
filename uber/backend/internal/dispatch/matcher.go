package dispatch

import (
	"context"
	"log/slog"
	"sync"
	"time"

	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/geo"
)

// MatcherConfig は matcher の動作パラメータ (test では小さく差し替える)。
// 既定値は ADR 0003 の「offer 10s タイムアウト / KRing(2)→(4) 拡大検索 / 全体 30s 打ち切り」。
type MatcherConfig struct {
	OfferTimeout    time.Duration // 1 offer につき accept を待つ時間
	InitialKRing    int           // 初期検索半径
	ExpandedKRing   int           // 拡大検索半径
	OverallDeadline time.Duration // この時間内に match できなければ no_driver_found
}

func DefaultMatcherConfig() MatcherConfig {
	return MatcherConfig{
		OfferTimeout:    10 * time.Second,
		InitialKRing:    2,
		ExpandedKRing:   4,
		OverallDeadline: 30 * time.Second,
	}
}

// Offer は driver の WS goroutine が受け取る offer メッセージ。
// driver client は WS で {op: "accept", trip_id} / {op: "reject", trip_id} を返す。
// Source は driver の応答を戻すべき matcher の参照 (ws code が
// offer.Source.HandleOfferResponse(...) を呼ぶことで matcher.offerResponses に流れる)。
type Offer struct {
	TripID     int64
	PickupLat  float64
	PickupLng  float64
	DropoffLat float64
	DropoffLng float64
	ExpiresAt  time.Time
	Source     *Matcher
}

// OfferResponse は driver からの accept/reject。
// 公開型にしたのは ws 等の外部 package から HandleOfferResponse を呼ぶため。
type OfferResponse struct {
	TripID       int64
	DriverUserID int64
	Accepted     bool
}

// driverState は matcher が cell ごとに専有する driver の in-memory state。
// このフィールドへの read/write はすべて matcher goroutine の文脈で行う (mutex なし)。
type driverState struct {
	userID  int64
	lat     float64
	lng     float64
	offerCh chan Offer // buffered, capacity 1. non-blocking send + drop で flood を吸収
}

// TripRequest は matcher.requests に投入される。
type TripRequest struct {
	TripID     int64
	PickupCell geo.Cell
	PickupLat  float64
	PickupLng  float64
	DropoffLat float64
	DropoffLng float64
}

// PositionUpdate は driver の位置更新通知。matcher が idle driver の cell 帰属を管理する。
//
// Cell が空 + Online=false → driver はオフラインになった (idleDrivers から除去)
// Cell が空 + Online=true  → driver は idle だが位置未報告 (登録のみ)
// Cell が非空              → driver の位置を更新 (idleDrivers の lat/lng を反映)
type PositionUpdate struct {
	DriverUserID int64
	Cell         geo.Cell
	Lat          float64
	Lng          float64
	Online       bool
	OfferCh      chan Offer // driver の WS goroutine が listen している chan
}

// Matcher は 1 つの H3 cell を担当する常駐 goroutine。
// 同 cell 内の idle driver と incoming trip request をシリアル化して捌く (ADR 0003)。
type Matcher struct {
	cell             geo.Cell
	cfg              MatcherConfig
	log              *slog.Logger
	acceptor         Acceptor // AcceptTrip 注入。test では fake に差し替え
	candidatesFn     CandidatesFn

	// channels (外部から push)
	requests        chan TripRequest
	positionUpdates chan PositionUpdate
	offerResponses  chan OfferResponse

	// goroutine 専有 state
	idleDrivers map[int64]*driverState
}

// Acceptor は trip / driver を accept commit する責務 (本番は dispatch.AcceptTrip)。
// test では fake で「常に勝つ」「常に負ける」を切り替える。
type Acceptor interface {
	AcceptTrip(ctx context.Context, tripID, driverUserID int64) (bool, error)
}

// CandidatesFn は cell + k-ring から候補 driver を列挙する関数。
// 戻り値の順序は近距離優先 (matcher は受け取り順に offer を送る)。
// matcher は cell の所属 driver しか知らないので、隣接 cell の matcher と協調する必要がある。
// 本ファイルでは「自 cell のみ」を返す simple 版を default にし、k-ring 拡張は test で差し替え可能にする。
type CandidatesFn func(matcher *Matcher, request TripRequest, k int) []*driverState

// NewMatcher は cell 1 つに対する matcher を生成する。Run() で開始しないと goroutine は走らない。
func NewMatcher(cell geo.Cell, cfg MatcherConfig, log *slog.Logger, acceptor Acceptor) *Matcher {
	return &Matcher{
		cell:            cell,
		cfg:             cfg,
		log:             log,
		acceptor:        acceptor,
		candidatesFn:    sameCellCandidates,
		requests:        make(chan TripRequest, 16),
		positionUpdates: make(chan PositionUpdate, 64),
		offerResponses:  make(chan OfferResponse, 64),
		idleDrivers:     map[int64]*driverState{},
	}
}

func sameCellCandidates(m *Matcher, _ TripRequest, _ int) []*driverState {
	out := make([]*driverState, 0, len(m.idleDrivers))
	for _, d := range m.idleDrivers {
		out = append(out, d)
	}
	return out
}

// SetCandidatesFn は test 用の差し替え hook。
func (m *Matcher) SetCandidatesFn(fn CandidatesFn) { m.candidatesFn = fn }

// Run は matcher の select loop。ctx 終了で停止する。
// すべての state access は本 goroutine 内で完結 → mutex 不要 (discord ADR 0002 と同パターン)。
func (m *Matcher) Run(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case req := <-m.requests:
			m.handleRequest(ctx, req)
		case pu := <-m.positionUpdates:
			m.applyPositionUpdate(pu)
		}
	}
}

// EnqueueRequest は外部 (HTTP handler) から trip を投入する。
func (m *Matcher) EnqueueRequest(req TripRequest) {
	m.requests <- req
}

// NotifyPosition は driver の WS goroutine / registry から位置更新を通知する。
func (m *Matcher) NotifyPosition(pu PositionUpdate) {
	select {
	case m.positionUpdates <- pu:
	default:
		// chan 満杯はサイレントに drop。次の position update でリカバリする想定 (4-10s に 1 回来る)。
		if m.log != nil {
			m.log.Warn("matcher: positionUpdates full, drop",
				slog.String("cell", string(m.cell)),
				slog.Int64("driver_id", pu.DriverUserID))
		}
	}
}

// HandleOfferResponse は driver の accept/reject を matcher に届ける。
// 外部 (ws 等) から Offer.Source.HandleOfferResponse(...) で呼ぶ。
func (m *Matcher) HandleOfferResponse(resp OfferResponse) {
	m.offerResponses <- resp
}

func (m *Matcher) applyPositionUpdate(pu PositionUpdate) {
	if !pu.Online {
		delete(m.idleDrivers, pu.DriverUserID)
		return
	}
	d, ok := m.idleDrivers[pu.DriverUserID]
	if !ok {
		d = &driverState{userID: pu.DriverUserID, offerCh: pu.OfferCh}
		m.idleDrivers[pu.DriverUserID] = d
	}
	d.lat = pu.Lat
	d.lng = pu.Lng
	if pu.OfferCh != nil {
		d.offerCh = pu.OfferCh
	}
}

// handleRequest は 1 trip request に対し:
//   1. InitialKRing → ExpandedKRing の順に候補を列挙
//   2. 各候補に offer を送る (non-blocking)、OfferTimeout だけ accept を待つ
//   3. accept されたら AcceptTrip で DB 反映、勝ったら終了
//   4. OverallDeadline までに勝者ゼロなら "no_driver_found" を返す (本関数はステータスを返すだけ、
//      実際の trip.canceled へ進める責務は呼び出し側 — Phase 3 では Trip cancel 処理は省略)
func (m *Matcher) handleRequest(ctx context.Context, req TripRequest) {
	deadline := time.Now().Add(m.cfg.OverallDeadline)
	rings := []int{m.cfg.InitialKRing, m.cfg.ExpandedKRing}

	for _, k := range rings {
		if time.Now().After(deadline) {
			return
		}
		candidates := m.candidatesFn(m, req, k)
		for _, d := range candidates {
			if time.Now().After(deadline) {
				return
			}
			expires := time.Now().Add(m.cfg.OfferTimeout)
			offer := Offer{
				TripID:     req.TripID,
				PickupLat:  req.PickupLat,
				PickupLng:  req.PickupLng,
				DropoffLat: req.DropoffLat,
				DropoffLng: req.DropoffLng,
				ExpiresAt:  expires,
				Source:     m,
			}
			// non-blocking send + drop (ADR 0003)
			select {
			case d.offerCh <- offer:
			default:
				continue // driver が忙しい、次の候補へ
			}
			// accept/reject 待ち
			if m.waitForAccept(ctx, req.TripID, d.userID, m.cfg.OfferTimeout) {
				// AcceptTrip で DB 反映 (compare-and-set 二段で race 解消)
				won, err := m.acceptor.AcceptTrip(ctx, req.TripID, d.userID)
				if err != nil {
					if m.log != nil {
						m.log.Error("matcher: AcceptTrip", slog.Any("err", err))
					}
					continue
				}
				if won {
					// 確定。matched driver は idleDrivers から外す
					delete(m.idleDrivers, d.userID)
					return
				}
				// 競合負け (driver が別 trip で先に matched / trip が既に cancel)。次へ
			}
		}
	}
	// すべての ring で勝者ゼロ — Phase 3 では呼び出し側で no_driver_found を扱う
}

// waitForAccept は offerResponses から (tripID, driverID) の応答を待つ。
// 他の trip/driver の応答が混じってくることがあるので、合致しないものは drop する
// (test の単純化のため strict match。実プロダクションでは queue に戻すなどの選択肢あり)。
func (m *Matcher) waitForAccept(ctx context.Context, tripID, driverID int64, timeout time.Duration) bool {
	t := time.NewTimer(timeout)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return false
		case <-t.C:
			return false
		case resp := <-m.offerResponses:
			if resp.TripID != tripID || resp.DriverUserID != driverID {
				continue
			}
			return resp.Accepted
		}
	}
}

// ---------- CellRegistry ----------

// CellRegistry は H3 cell → Matcher の lookup を集約する。
// lazy create (最初の request / position が来た cell に対して NewMatcher + go Run)。
// Stop による graceful shutdown は呼び出し側で ctx cancel すれば全 Matcher が停止する。
type CellRegistry struct {
	mu       sync.Mutex
	matchers map[geo.Cell]*Matcher

	ctx       context.Context
	cfg       MatcherConfig
	log       *slog.Logger
	acceptor  Acceptor
}

func NewCellRegistry(ctx context.Context, cfg MatcherConfig, log *slog.Logger, acceptor Acceptor) *CellRegistry {
	return &CellRegistry{
		matchers: map[geo.Cell]*Matcher{},
		ctx:      ctx,
		cfg:      cfg,
		log:      log,
		acceptor: acceptor,
	}
}

// GetOrCreate は cell 用の matcher を返す。存在しなければ作成して go Run する。
func (r *CellRegistry) GetOrCreate(cell geo.Cell) *Matcher {
	r.mu.Lock()
	defer r.mu.Unlock()
	if m, ok := r.matchers[cell]; ok {
		return m
	}
	m := NewMatcher(cell, r.cfg, r.log, r.acceptor)
	r.matchers[cell] = m
	go m.Run(r.ctx)
	if r.log != nil {
		r.log.Info("matcher: started", slog.String("cell", string(cell)))
	}
	return m
}

// Len は active な matcher 数。test 用。
func (r *CellRegistry) Len() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return len(r.matchers)
}
