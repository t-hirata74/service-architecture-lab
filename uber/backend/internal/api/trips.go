package api

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/dispatch"
	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/geo"
	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/store"
)

type tripCreateBody struct {
	PickupLat  float64 `json:"pickup_lat"`
	PickupLng  float64 `json:"pickup_lng"`
	DropoffLat float64 `json:"dropoff_lat"`
	DropoffLng float64 `json:"dropoff_lng"`
}

func validCoord(lat, lng float64) bool {
	return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180
}

// PostTrip は rider が新規 trip を要求する。
//   1. lat/lng 検証 + H3 cell 計算
//   2. store.CreateTrip (status=requested)
//   3. dispatch.TransitionTrip で requested → matching へ + trip_event(matching_started) 記録
//   4. CellRegistry.GetOrCreate(cell).EnqueueRequest(...) で matcher へ投入
//
// 戻り値は trip_id を含む 201 created。matching の完了は async (poll or WS で確認)。
func (h *Handler) PostTrip(w http.ResponseWriter, r *http.Request) {
	uid, ok := h.requireUID(w, r)
	if !ok {
		return
	}
	role, _ := RoleFromContext(r.Context())
	if role != string(store.RoleRider) {
		jsonError(w, http.StatusForbidden, "only riders can create trips")
		return
	}

	var body tripCreateBody
	if err := readJSON(r, &body); err != nil {
		jsonError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if !validCoord(body.PickupLat, body.PickupLng) || !validCoord(body.DropoffLat, body.DropoffLng) {
		jsonError(w, http.StatusBadRequest, "coordinates out of range")
		return
	}

	pickupCell, err := geo.Encode(body.PickupLat, body.PickupLng, h.H3Resolution)
	if err != nil {
		jsonError(w, http.StatusBadRequest, "invalid coordinates")
		return
	}

	tripID, err := h.Store.CreateTrip(r.Context(), uid,
		body.PickupLat, body.PickupLng, string(pickupCell),
		body.DropoffLat, body.DropoffLng)
	if err != nil {
		h.Log.Error("create trip", slog.Any("err", err))
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}

	// requested → matching に進めて matcher に渡せる状態にする
	won, err := dispatch.TransitionTrip(r.Context(), h.Store, tripID,
		dispatch.TripRequested, dispatch.TripMatching,
		&uid, nil, "matching_started", nil)
	if err != nil || !won {
		// 直後の状態なので普通起こらないが、起こったら 500 で記録
		h.Log.Error("matching transition", slog.Any("err", err), slog.Bool("won", won))
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}

	// matcher に enqueue (Registry 未注入 = test 経路など、では enqueue を skip)
	if h.Registry != nil {
		m := h.Registry.GetOrCreate(pickupCell)
		m.EnqueueRequest(dispatch.TripRequest{
			TripID:     tripID,
			PickupCell: pickupCell,
			PickupLat:  body.PickupLat,
			PickupLng:  body.PickupLng,
			DropoffLat: body.DropoffLat,
			DropoffLng: body.DropoffLng,
		})
	}

	tr, err := h.Store.TripByID(r.Context(), tripID)
	if err != nil {
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	jsonWrite(w, http.StatusCreated, map[string]any{"trip": tripView(tr)})
}

// GetTrip は rider 本人または assigned driver のみ閲覧可。
// それ以外は 404 で「存在しないように見せる」(認可漏洩を avoid)。
func (h *Handler) GetTrip(w http.ResponseWriter, r *http.Request) {
	uid, ok := h.requireUID(w, r)
	if !ok {
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		jsonError(w, http.StatusBadRequest, "invalid id")
		return
	}
	tr, err := h.Store.TripByID(r.Context(), id)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			jsonError(w, http.StatusNotFound, "trip not found")
			return
		}
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	if tr.RiderID != uid && (tr.DriverID == nil || *tr.DriverID != uid) {
		jsonError(w, http.StatusNotFound, "trip not found")
		return
	}
	jsonWrite(w, http.StatusOK, map[string]any{"trip": tripView(tr)})
}

// PostTripCancel は rider 主導のキャンセル。
// driver_accepted 以降のキャンセルでは driver も idle に戻す必要があるが、
// driver の compare-and-set 失敗 (例: 既に on_trip) は許容できない race なので、
// 本実装では trip の cancel が成功した時点で driver を idle に戻す best-effort を試みる。
func (h *Handler) PostTripCancel(w http.ResponseWriter, r *http.Request) {
	uid, ok := h.requireUID(w, r)
	if !ok {
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		jsonError(w, http.StatusBadRequest, "invalid id")
		return
	}
	tr, err := h.Store.TripByID(r.Context(), id)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			jsonError(w, http.StatusNotFound, "trip not found")
			return
		}
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	if tr.RiderID != uid {
		jsonError(w, http.StatusForbidden, "only the rider can cancel this trip")
		return
	}
	if tr.Status == string(dispatch.TripCompleted) || tr.Status == string(dispatch.TripCanceled) {
		jsonError(w, http.StatusConflict, "trip already terminal")
		return
	}

	// 現在の status から canceled へ。in_trip からの cancel は禁止する (本実装では)。
	if tr.Status == string(dispatch.TripInTrip) {
		jsonError(w, http.StatusConflict, "cannot cancel an in-trip ride")
		return
	}

	from := dispatch.TripStatus(tr.Status)
	reason := "rider"
	canceledAt := nowProvider()

	won, err := dispatch.TransitionTrip(r.Context(), h.Store, id,
		from, dispatch.TripCanceled,
		&uid,
		[]store.SetClause{
			{Column: "canceled_reason", Value: reason},
			{Column: "canceled_at", Value: canceledAt},
		},
		"canceled",
		nil,
	)
	if err != nil {
		h.Log.Error("cancel transition", slog.Any("err", err))
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	if !won {
		// 他の actor が同時に進めた (e.g. driver が accept していた) → 現状を読み直して返す
		fresh, _ := h.Store.TripByID(r.Context(), id)
		jsonWrite(w, http.StatusConflict, map[string]any{
			"error": "trip state changed concurrently",
			"trip":  tripView(fresh),
		})
		return
	}

	// driver が assigned だった場合は idle に戻す best-effort
	if tr.DriverID != nil {
		_, _ = dispatch.TransitionDriver(r.Context(), h.Store, *tr.DriverID,
			dispatch.DriverMatched, dispatch.DriverIdle,
			store.SetClause{Column: "current_trip_id", Value: nil},
		)
		// failure は容認 (driver が既に別 trip に進んでいる等)
	}

	fresh, _ := h.Store.TripByID(r.Context(), id)
	jsonWrite(w, http.StatusOK, map[string]any{"trip": tripView(fresh)})
}

// nowProvider は test で差し替え可能な時刻取得。
var nowProvider = defaultNow

func tripView(t *store.Trip) map[string]any {
	return map[string]any{
		"id":              t.ID,
		"rider_id":        t.RiderID,
		"driver_id":       t.DriverID,
		"status":          t.Status,
		"pickup_lat":      t.PickupLat,
		"pickup_lng":      t.PickupLng,
		"pickup_h3_cell":  t.PickupH3Cell,
		"dropoff_lat":     t.DropoffLat,
		"dropoff_lng":     t.DropoffLng,
		"fare_cents":      t.FareCents,
		"canceled_reason": t.CanceledReason,
		"requested_at":    t.RequestedAt,
		"matched_at":      t.MatchedAt,
		"completed_at":    t.CompletedAt,
		"canceled_at":     t.CanceledAt,
	}
}
