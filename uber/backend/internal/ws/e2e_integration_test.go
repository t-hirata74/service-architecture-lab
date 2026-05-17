package ws

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-sql-driver/mysql"
	gws "github.com/gorilla/websocket"

	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/api"
	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/dispatch"
	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/store"
)

// 完全な E2E (rider が POST /trips → driver が WS で offer 受信 → accept →
// rider が GET /trips/:id で driver_accepted を確認) を MySQL 実機で通す。
//
// UBER_TEST_DB env が無ければ skip。
func openE2EServer(t *testing.T) (string, *store.Store, func()) {
	t.Helper()
	dsn := os.Getenv("UBER_TEST_DB")
	if dsn == "" {
		t.Skip("UBER_TEST_DB not set")
	}
	mc, _ := mysql.ParseDSN(dsn)
	db, err := sql.Open("mysql", mc.FormatDSN())
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	if err := db.Ping(); err != nil {
		t.Fatalf("ping: %v", err)
	}
	st := &store.Store{DB: db}
	log := slog.New(slog.NewTextHandler(io.Discard, nil))

	matcherCtx, matcherCancel := context.WithCancel(context.Background())
	acceptor := &dispatch.StoreAcceptor{Store: st}
	// テスト用に offer timeout を短くする (10s だと test が遅い)
	cfg := dispatch.MatcherConfig{
		OfferTimeout:    1 * time.Second,
		InitialKRing:    0,
		ExpandedKRing:   0,
		OverallDeadline: 5 * time.Second,
	}
	registry := dispatch.NewCellRegistry(matcherCtx, cfg, log, acceptor)

	h := api.NewHandler(log, st, []byte("e2e-secret-do-not-use-in-prod"))
	h.Registry = registry
	h.H3Resolution = 9

	gw := &Service{
		Log: log, Store: st, JWTSecret: []byte("e2e-secret-do-not-use-in-prod"),
		Registry: registry, H3Resolution: 9,
		AllowedOrigins: []string{}, // empty = allow all
	}

	root := chi.NewRouter()
	root.Get("/ws", gw.HandleWS)
	root.Mount("/", h.Routes())

	srv := httptest.NewServer(root)
	cleanup := func() {
		srv.Close()
		matcherCancel()
		_ = db.Close()
	}
	return srv.URL, st, cleanup
}

func registerAndLogin(t *testing.T, baseURL, role, email string) (token string, userID int64) {
	t.Helper()
	body := map[string]any{
		"email":        email,
		"password":     "e2e-pw-12345",
		"role":         role,
		"display_name": "E2E " + role,
	}
	raw, _ := json.Marshal(body)
	resp, err := http.Post(baseURL+"/auth/register", "application/json", bytes.NewReader(raw))
	if err != nil {
		t.Fatalf("register: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		b, _ := io.ReadAll(resp.Body)
		t.Fatalf("register status %d body=%s", resp.StatusCode, string(b))
	}
	var rr struct {
		Token string `json:"token"`
		User  struct {
			ID int64 `json:"id"`
		} `json:"user"`
	}
	_ = json.NewDecoder(resp.Body).Decode(&rr)
	return rr.Token, rr.User.ID
}

// E2E test の本体。
func TestE2E_RiderRequest_DriverAccepts(t *testing.T) {
	baseURL, st, cleanup := openE2EServer(t)
	defer cleanup()

	ctx := context.Background()
	suffix := strconv.FormatInt(time.Now().UnixNano(), 10)

	// 1. driver と rider を登録
	driverToken, driverID := registerAndLogin(t, baseURL, "driver", "driver-"+suffix+"@e2e.local")
	riderToken, _ := registerAndLogin(t, baseURL, "rider", "rider-"+suffix+"@e2e.local")

	// 2. driver WS 接続 (?token=)
	wsURL := strings.Replace(baseURL, "http://", "ws://", 1) + "/ws?token=" + url.QueryEscape(driverToken)
	wsConn, _, err := gws.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("ws dial: %v", err)
	}
	defer wsConn.Close()

	// 初期 hello を受け取る
	var hello Outbound
	wsConn.SetReadDeadline(time.Now().Add(2 * time.Second))
	if err := wsConn.ReadJSON(&hello); err != nil {
		t.Fatalf("hello: %v", err)
	}
	if hello.Op != OpHello || hello.UserID != driverID {
		t.Fatalf("hello mismatch: %+v", hello)
	}

	// 3. driver go_online (pickup 周辺の位置)
	pickupLat, pickupLng := 35.6812, 139.7671
	if err := wsConn.WriteJSON(Inbound{Op: OpGoOnline, Lat: pickupLat, Lng: pickupLng}); err != nil {
		t.Fatalf("go_online: %v", err)
	}

	// driver が idle になるまで少し待つ (DB transition + matcher 登録)
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		d, err := st.DriverByUserID(ctx, driverID)
		if err == nil && d.Status == "idle" {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	d, err := st.DriverByUserID(ctx, driverID)
	if err != nil || d.Status != "idle" {
		t.Fatalf("driver should be idle, got %+v err=%v", d, err)
	}

	// 4. rider が POST /trips
	tripBody, _ := json.Marshal(map[string]any{
		"pickup_lat":  pickupLat,
		"pickup_lng":  pickupLng,
		"dropoff_lat": 35.6896,
		"dropoff_lng": 139.7006,
	})
	req, _ := http.NewRequest("POST", baseURL+"/trips", bytes.NewReader(tripBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+riderToken)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("post trip: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		b, _ := io.ReadAll(resp.Body)
		t.Fatalf("post trip status %d body=%s", resp.StatusCode, string(b))
	}
	var trResp struct {
		Trip struct {
			ID int64 `json:"id"`
		} `json:"trip"`
	}
	_ = json.NewDecoder(resp.Body).Decode(&trResp)
	tripID := trResp.Trip.ID
	if tripID == 0 {
		t.Fatal("trip id zero")
	}

	// 5. driver が offer を受信
	wsConn.SetReadDeadline(time.Now().Add(3 * time.Second))
	var offer Outbound
	if err := wsConn.ReadJSON(&offer); err != nil {
		t.Fatalf("read offer: %v", err)
	}
	if offer.Op != OpOffer {
		t.Fatalf("expected offer op, got %s (%+v)", offer.Op, offer)
	}
	if offer.TripID != tripID {
		t.Fatalf("offer trip_id = %d, want %d", offer.TripID, tripID)
	}

	// 6. driver が accept
	if err := wsConn.WriteJSON(Inbound{Op: OpAccept, TripID: tripID}); err != nil {
		t.Fatalf("accept: %v", err)
	}

	// 7. rider が GET /trips/:id を poll、driver_accepted になるのを確認
	deadline = time.Now().Add(3 * time.Second)
	var finalStatus string
	for time.Now().Before(deadline) {
		gReq, _ := http.NewRequest("GET", baseURL+"/trips/"+strconv.FormatInt(tripID, 10), nil)
		gReq.Header.Set("Authorization", "Bearer "+riderToken)
		gResp, err := http.DefaultClient.Do(gReq)
		if err == nil && gResp.StatusCode == 200 {
			var gr struct {
				Trip struct {
					Status   string `json:"status"`
					DriverID *int64 `json:"driver_id"`
				} `json:"trip"`
			}
			_ = json.NewDecoder(gResp.Body).Decode(&gr)
			gResp.Body.Close()
			if gr.Trip.Status == "driver_accepted" && gr.Trip.DriverID != nil && *gr.Trip.DriverID == driverID {
				finalStatus = gr.Trip.Status
				break
			}
		} else if gResp != nil {
			gResp.Body.Close()
		}
		time.Sleep(50 * time.Millisecond)
	}
	if finalStatus != "driver_accepted" {
		t.Fatalf("final trip status = %q, want driver_accepted", finalStatus)
	}

	// driver も matched
	d2, _ := st.DriverByUserID(ctx, driverID)
	if d2.Status != "matched" {
		t.Errorf("driver status = %s, want matched", d2.Status)
	}
	if d2.CurrentTripID == nil || *d2.CurrentTripID != tripID {
		t.Errorf("driver.current_trip_id = %v, want %d", d2.CurrentTripID, tripID)
	}
}
