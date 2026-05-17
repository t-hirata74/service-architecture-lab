package dispatch

import (
	"context"
	"database/sql"
	"os"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/go-sql-driver/mysql"

	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/store"
)

// 統合テストは UBER_TEST_DB 環境変数 (例: "uber:uber@tcp(127.0.0.1:3327)/uber_test?parseTime=true")
// が設定されているときだけ走る。docker compose で MySQL 起動 + migrations 適用 + uber_test DB を
// 作っておく前提。CI では Phase 5 で別途配線する。
//
// テスト前に Schema が空である必要はないが、用意する driver / trip / user は
// id を毎回ユニークに振るため (timestamp ベース) 既存データと衝突しない。
func openTestDB(t *testing.T) *sql.DB {
	t.Helper()
	dsn := os.Getenv("UBER_TEST_DB")
	if dsn == "" {
		t.Skip("UBER_TEST_DB not set, skipping integration test")
	}
	mc, err := mysql.ParseDSN(dsn)
	if err != nil {
		t.Fatalf("parse dsn: %v", err)
	}
	mc.MultiStatements = false
	db, err := sql.Open("mysql", mc.FormatDSN())
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	if err := db.Ping(); err != nil {
		t.Fatalf("ping: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })
	return db
}

func setupRiderAndDriver(t *testing.T, st *store.Store) (riderID, driverID int64) {
	t.Helper()
	ctx := context.Background()
	suffix := time.Now().UnixNano()
	r, err := st.CreateUser(ctx, fakeEmail("rider", suffix), "h", store.RoleRider, "Test Rider")
	if err != nil {
		t.Fatalf("create rider: %v", err)
	}
	d, err := st.CreateUser(ctx, fakeEmail("driver", suffix), "h", store.RoleDriver, "Test Driver")
	if err != nil {
		t.Fatalf("create driver user: %v", err)
	}
	if err := st.CreateDriver(ctx, d); err != nil {
		t.Fatalf("create driver: %v", err)
	}
	// driver を idle に
	if _, err := st.CompareAndSetDriverStatus(ctx, nil, d,
		string(DriverOffline), string(DriverIdle)); err != nil {
		t.Fatalf("driver idle: %v", err)
	}
	return r, d
}

func fakeEmail(role string, nano int64) string {
	return role + "-" + itoa(nano) + "@test.local"
}

// itoa: strconv.Itoa(int64) は無いので簡易に
func itoa(n int64) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	digits := make([]byte, 0, 20)
	for n > 0 {
		digits = append([]byte{byte('0' + n%10)}, digits...)
		n /= 10
	}
	if neg {
		digits = append([]byte{'-'}, digits...)
	}
	return string(digits)
}

// 100 goroutine が同じ driver を accept しようとして、勝者が 1 だけになることを検証 (ADR 0002 の中心)。
// ただし trip は 100 件別々に作る (1 driver が複数 trip から取り合われる構図)。
func TestIntegration_AcceptTrip_Concurrent(t *testing.T) {
	db := openTestDB(t)
	st := &store.Store{DB: db}
	ctx := context.Background()

	// rider + driver を作る
	rider, driver := setupRiderAndDriver(t, st)

	// 100 trip を作って matching 状態に進める (rider 1 人で 100 trip もおかしいが、テスト用なので許容)
	const N = 100
	tripIDs := make([]int64, N)
	for i := 0; i < N; i++ {
		id, err := st.CreateTrip(ctx, rider, 35.6812, 139.7671, "8a2a1072b59ffff", 35.6896, 139.7006)
		if err != nil {
			t.Fatalf("create trip[%d]: %v", i, err)
		}
		tripIDs[i] = id
		// requested -> matching
		won, err := TransitionTrip(ctx, st, id,
			TripRequested, TripMatching, nil, nil, "matching_started", nil)
		if err != nil || !won {
			t.Fatalf("matching: won=%v err=%v", won, err)
		}
	}

	// 100 goroutine が同じ driver に対して accept を試みる
	var wins atomic.Int32
	var losses atomic.Int32
	start := make(chan struct{})
	var wg sync.WaitGroup
	for i := 0; i < N; i++ {
		wg.Add(1)
		tripID := tripIDs[i]
		go func() {
			defer wg.Done()
			<-start
			won, err := AcceptTrip(ctx, st, tripID, driver)
			if err != nil {
				t.Errorf("AcceptTrip err: %v", err)
				return
			}
			if won {
				wins.Add(1)
			} else {
				losses.Add(1)
			}
		}()
	}
	close(start)
	wg.Wait()

	if w := wins.Load(); w != 1 {
		t.Errorf("expected exactly 1 winner, got %d", w)
	}
	if l := losses.Load(); l != N-1 {
		t.Errorf("expected %d losers, got %d", N-1, l)
	}

	// driver が matched 状態にあること + driver_id がどれかの trip に紐付いていること
	d, err := st.DriverByUserID(ctx, driver)
	if err != nil {
		t.Fatalf("DriverByUserID: %v", err)
	}
	if d.Status != string(DriverMatched) {
		t.Errorf("driver status = %s, want matched", d.Status)
	}

	// 当選した trip だけが driver_accepted、残りは matching のまま
	var accepted, stillMatching int
	for _, id := range tripIDs {
		tr, err := st.TripByID(ctx, id)
		if err != nil {
			t.Fatalf("TripByID: %v", err)
		}
		switch tr.Status {
		case string(TripDriverAccepted):
			accepted++
		case string(TripMatching):
			stillMatching++
		}
	}
	if accepted != 1 {
		t.Errorf("expected 1 accepted, got %d", accepted)
	}
	if stillMatching != N-1 {
		t.Errorf("expected %d still matching, got %d", N-1, stillMatching)
	}
}
