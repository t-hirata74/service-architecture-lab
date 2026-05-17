package ws

import (
	"context"
	"encoding/json"
	"log/slog"
	"sync"
	"time"

	"github.com/gorilla/websocket"

	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/dispatch"
	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/geo"
	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/store"
)

// driverConn は 1 件の WS 接続を表す per-connection state。
// すべてのフィールド read/write は 2 つの goroutine (readPump / writePump) に分離。
// 共有資源 (writeMu / pendingByTrip / currentCell) は mutex で守る。
type driverConn struct {
	conn   *websocket.Conn
	userID int64

	offerCh chan dispatch.Offer // matcher → write goroutine

	// pendingByTrip: trip_id ごとに「どの matcher へ accept/reject を返すか」を覚える
	pendingMu     sync.Mutex
	pendingByTrip map[int64]*dispatch.Matcher

	writeMu sync.Mutex
	log     *slog.Logger

	store        *store.Store
	registry     *dispatch.CellRegistry
	h3Resolution int

	cellMu      sync.Mutex
	currentCell geo.Cell // driver が現在いる cell (matcher 登録先)

	closeOnce sync.Once
	readDone  chan struct{}
}

func (dc *driverConn) writeJSON(v any) error {
	dc.writeMu.Lock()
	defer dc.writeMu.Unlock()
	_ = dc.conn.SetWriteDeadline(time.Now().Add(writeWait))
	return dc.conn.WriteJSON(v)
}

func (dc *driverConn) close() {
	dc.closeOnce.Do(func() {
		_ = dc.conn.Close()
		close(dc.readDone)
	})
}

// readPump は WS から読み取り、op に応じて matcher / DB を更新する。
// 接続終了時 (read エラー / context cancel) には driver を offline に戻す。
func (dc *driverConn) readPump(ctx context.Context) {
	defer func() {
		dc.markOffline(ctx)
		dc.close()
	}()
	for {
		_, raw, err := dc.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				dc.logErr("ws read", err)
			}
			return
		}
		var in Inbound
		if err := json.Unmarshal(raw, &in); err != nil {
			_ = dc.writeJSON(Outbound{Op: OpError, Message: "invalid json"})
			continue
		}
		switch in.Op {
		case OpGoOnline:
			dc.handleGoOnline(ctx, in)
		case OpPosition:
			dc.handlePosition(ctx, in)
		case OpAccept:
			dc.handleResponse(in.TripID, true)
		case OpReject:
			dc.handleResponse(in.TripID, false)
		case OpGoOffline:
			dc.markOffline(ctx)
			return
		default:
			_ = dc.writeJSON(Outbound{Op: OpError, Message: "unknown op: " + string(in.Op)})
		}
	}
}

// writePump は offerCh から offer を取って WS に書き出す + ping を定期送信する。
func (dc *driverConn) writePump(ctx context.Context) {
	ticker := time.NewTicker(pingPeriod)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-dc.readDone:
			return
		case <-ticker.C:
			dc.writeMu.Lock()
			_ = dc.conn.SetWriteDeadline(time.Now().Add(writeWait))
			err := dc.conn.WriteMessage(websocket.PingMessage, nil)
			dc.writeMu.Unlock()
			if err != nil {
				return
			}
		case offer, ok := <-dc.offerCh:
			if !ok {
				return
			}
			// pending に保存して、後で accept/reject 来たら offer.Source へ routing する
			dc.pendingMu.Lock()
			dc.pendingByTrip[offer.TripID] = offer.Source
			dc.pendingMu.Unlock()

			out := Outbound{
				Op:         OpOffer,
				TripID:     offer.TripID,
				PickupLat:  offer.PickupLat,
				PickupLng:  offer.PickupLng,
				DropoffLat: offer.DropoffLat,
				DropoffLng: offer.DropoffLng,
				ExpiresAt:  offer.ExpiresAt.UTC().Format(time.RFC3339Nano),
			}
			if err := dc.writeJSON(out); err != nil {
				dc.logErr("ws write offer", err)
				return
			}
		}
	}
}

func (dc *driverConn) handleGoOnline(ctx context.Context, in Inbound) {
	cell, err := geo.Encode(in.Lat, in.Lng, dc.h3Resolution)
	if err != nil {
		_ = dc.writeJSON(Outbound{Op: OpError, Message: "invalid position"})
		return
	}
	// DB: status offline → idle (compare-and-set) + position 更新
	won, err := dispatch.TransitionDriver(ctx, dc.store, dc.userID,
		dispatch.DriverOffline, dispatch.DriverIdle)
	if err != nil {
		dc.logErr("go_online transition", err)
		_ = dc.writeJSON(Outbound{Op: OpError, Message: "internal error"})
		return
	}
	if !won {
		// 既に idle 等。冪等 no-op として続行 (DB 状態を信頼する)
	}
	if err := dc.store.UpdateDriverPosition(ctx, dc.userID, string(cell), in.Lat, in.Lng); err != nil {
		dc.logErr("update position", err)
	}
	// matcher 登録
	dc.cellMu.Lock()
	dc.currentCell = cell
	dc.cellMu.Unlock()
	m := dc.registry.GetOrCreate(cell)
	m.NotifyPosition(dispatch.PositionUpdate{
		DriverUserID: dc.userID,
		Cell:         cell,
		Lat:          in.Lat, Lng: in.Lng,
		Online:  true,
		OfferCh: dc.offerCh,
	})
}

func (dc *driverConn) handlePosition(ctx context.Context, in Inbound) {
	cell, err := geo.Encode(in.Lat, in.Lng, dc.h3Resolution)
	if err != nil {
		_ = dc.writeJSON(Outbound{Op: OpError, Message: "invalid position"})
		return
	}
	if err := dc.store.UpdateDriverPosition(ctx, dc.userID, string(cell), in.Lat, in.Lng); err != nil {
		dc.logErr("update position", err)
	}

	// cell 変更時は旧 matcher で go_offline 相当、新 matcher で go_online 相当
	dc.cellMu.Lock()
	old := dc.currentCell
	dc.currentCell = cell
	dc.cellMu.Unlock()

	if old != "" && old != cell {
		oldM := dc.registry.GetOrCreate(old)
		oldM.NotifyPosition(dispatch.PositionUpdate{DriverUserID: dc.userID, Online: false})
	}
	m := dc.registry.GetOrCreate(cell)
	m.NotifyPosition(dispatch.PositionUpdate{
		DriverUserID: dc.userID,
		Cell:         cell,
		Lat:          in.Lat, Lng: in.Lng,
		Online:  true,
		OfferCh: dc.offerCh,
	})
}

func (dc *driverConn) handleResponse(tripID int64, accepted bool) {
	dc.pendingMu.Lock()
	m, ok := dc.pendingByTrip[tripID]
	if ok {
		delete(dc.pendingByTrip, tripID)
	}
	dc.pendingMu.Unlock()

	if !ok || m == nil {
		_ = dc.writeJSON(Outbound{Op: OpError, Message: "no pending offer for that trip"})
		return
	}
	m.HandleOfferResponse(dispatch.OfferResponse{
		TripID: tripID, DriverUserID: dc.userID, Accepted: accepted,
	})
}

// markOffline は WS 切断 / go_offline 時の cleanup。
// idle 状態の driver を offline に戻し、matcher の idleDrivers から除く。
// matched / en_route / on_trip 状態の driver は status を変更しない (進行中 trip があるため)。
func (dc *driverConn) markOffline(ctx context.Context) {
	d, err := dc.store.DriverByUserID(ctx, dc.userID)
	if err == nil && d.Status == string(dispatch.DriverIdle) {
		_, _ = dispatch.TransitionDriver(ctx, dc.store, dc.userID,
			dispatch.DriverIdle, dispatch.DriverOffline)
	}
	dc.cellMu.Lock()
	if dc.currentCell != "" {
		m := dc.registry.GetOrCreate(dc.currentCell)
		dc.cellMu.Unlock()
		m.NotifyPosition(dispatch.PositionUpdate{DriverUserID: dc.userID, Online: false})
	} else {
		dc.cellMu.Unlock()
	}
}

func (dc *driverConn) logErr(msg string, err error) {
	if dc.log == nil {
		return
	}
	dc.log.Error(msg, slog.Int64("driver_id", dc.userID), slog.Any("err", err))
}
