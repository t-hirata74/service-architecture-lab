package ws

import (
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"

	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/auth"
	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/dispatch"
	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/store"
)

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = (pongWait * 9) / 10
	maxMessageSize = 1024
)

// Service は driver WebSocket gateway。
// rider は本 Phase ではスコープ外 (poll で代替)。
type Service struct {
	Log            *slog.Logger
	Store          *store.Store
	JWTSecret      []byte
	Registry       *dispatch.CellRegistry
	H3Resolution   int
	AllowedOrigins []string
}

func (s *Service) upgrader() *websocket.Upgrader {
	return &websocket.Upgrader{
		ReadBufferSize:  1024,
		WriteBufferSize: 1024,
		CheckOrigin: func(r *http.Request) bool {
			if len(s.AllowedOrigins) == 0 {
				return true // test 環境で許容
			}
			origin := r.Header.Get("Origin")
			for _, ao := range s.AllowedOrigins {
				if origin == ao {
					return true
				}
			}
			return false
		},
	}
}

// HandleWS は /ws のエンドポイント。?token=<jwt> で driver 認証。
//
// 流れ:
//  1. token を query string から取得 → ParseUserToken (REST と同じ secret)
//  2. role=driver でなければ 4001 close
//  3. driver の DB row 存在を確認 (CreateUser 後に drivers 行が無いケースを弾く)
//  4. offerCh / pendingByTrip を持つ per-connection state を生成
//  5. read / write goroutine を spawn、終了時に matcher へ go_offline 相当の通知
func (s *Service) HandleWS(w http.ResponseWriter, r *http.Request) {
	rawToken := strings.TrimSpace(r.URL.Query().Get("token"))
	if rawToken == "" {
		http.Error(w, "missing token", http.StatusUnauthorized)
		return
	}
	cl, err := auth.ParseUserToken(s.JWTSecret, rawToken)
	if err != nil {
		http.Error(w, "invalid token", http.StatusUnauthorized)
		return
	}
	if cl.Role != string(store.RoleDriver) {
		http.Error(w, "driver role required", http.StatusForbidden)
		return
	}
	if _, err := s.Store.DriverByUserID(r.Context(), cl.UserID); err != nil {
		http.Error(w, "driver row missing", http.StatusForbidden)
		return
	}

	conn, err := s.upgrader().Upgrade(w, r, nil)
	if err != nil {
		// upgrade 失敗時は既に http error が書かれている
		return
	}
	conn.SetReadLimit(maxMessageSize)
	_ = conn.SetReadDeadline(time.Now().Add(pongWait))
	conn.SetPongHandler(func(string) error {
		return conn.SetReadDeadline(time.Now().Add(pongWait))
	})

	dc := &driverConn{
		conn:           conn,
		userID:         cl.UserID,
		offerCh:        make(chan dispatch.Offer, 1), // 1 つ pending を許す
		pendingByTrip:  map[int64]*dispatch.Matcher{},
		writeMu:        sync.Mutex{},
		log:            s.Log,
		store:          s.Store,
		registry:       s.Registry,
		h3Resolution:   s.H3Resolution,
		currentCell:    "",
		closeOnce:      sync.Once{},
		readDone:       make(chan struct{}),
	}

	// 初期 hello
	_ = dc.writeJSON(Outbound{Op: OpHello, UserID: cl.UserID, Role: cl.Role})

	go dc.writePump(r.Context())
	dc.readPump(r.Context()) // blocks until disconnect
}
