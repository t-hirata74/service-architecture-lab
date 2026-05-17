package dispatch

import (
	"context"
	"errors"
	"fmt"

	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/store"
)

// ErrIllegalTransition は遷移マップで許可されていない遷移を試みた場合に返す。
// 「DB の現状とは無関係に、コードの宣言上 illegal」という意味。
// 一方、compare-and-set の affected rows = 0 はエラーではなく `won = false` で表現する (ADR 0002)。
var ErrIllegalTransition = errors.New("dispatch: illegal transition")

// TransitionTrip は trip の状態を compare-and-set で進め、同一トランザクションで
// trip_events に audit event を append する。
//
// 戻り値 won:
//   - true:  affected rows = 1。状態が from → to に確定し、event を 1 件記録した
//   - false: affected rows = 0。他で確定済み (冪等 no-op の発火点)。event は記録しない
//
// extras は同 UPDATE に乗せる追加列 (driver_id / matched_at / completed_at / canceled_reason 等)。
func TransitionTrip(
	ctx context.Context,
	st *store.Store,
	tripID int64,
	from, to TripStatus,
	actor *int64,
	extras []store.SetClause,
	eventType string,
	payloadJSON []byte,
) (won bool, err error) {
	if !IsValidTripTransition(from, to) {
		return false, fmt.Errorf("%w: trip %s -> %s", ErrIllegalTransition, from, to)
	}

	tx, err := st.DB.BeginTx(ctx, nil)
	if err != nil {
		return false, err
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	won, err = st.CompareAndSetTripStatus(ctx, tx, tripID, string(from), string(to), extras...)
	if err != nil {
		return false, err
	}
	if !won {
		// 他で確定済み — rollback して終了 (冪等 no-op)
		_ = tx.Rollback()
		return false, nil
	}

	if err = st.InsertTripEvent(ctx, tx, tripID, eventType, actor, payloadJSON); err != nil {
		return false, err
	}
	if err = tx.Commit(); err != nil {
		return false, err
	}
	return true, nil
}

// TransitionDriver は driver の status を compare-and-set で進める。
// trip_events 相当の driver 専用イベント表は本リポでは持たず、状態遷移は trip 側の
// trip_event (accept_committed / completed / canceled) で十分に追跡できると判断する (ADR 0002 でスコープ確定)。
//
// extras には current_trip_id 設定 (matched 時) / クリア (idle 戻り時) 等を乗せる。
func TransitionDriver(
	ctx context.Context,
	st *store.Store,
	userID int64,
	from, to DriverStatus,
	extras ...store.SetClause,
) (won bool, err error) {
	if !IsValidDriverTransition(from, to) {
		return false, fmt.Errorf("%w: driver %s -> %s", ErrIllegalTransition, from, to)
	}

	return st.CompareAndSetDriverStatus(ctx, nil, userID, string(from), string(to), extras...)
}

// AcceptTrip は driver が offer を accept した時の確定処理 (ADR 0002 の中心パターン)。
// 1. drivers: idle -> matched (compare-and-set)
// 2. trips:   matching -> driver_accepted (compare-and-set、driver_id と matched_at を同時 SET)
// 3. trip_events: accept_committed を append
// すべて同一 Tx。どちらか 1 つでも 0 行更新なら全 rollback して won=false を返す。
//
// 同一 driver に複数 trip からの accept が来ても、最初に COMMIT した側が勝者となる。
// 同一 trip に複数 driver が accept しても、最初に matching -> driver_accepted を取った側が勝者。
func AcceptTrip(ctx context.Context, st *store.Store, tripID, driverUserID int64) (won bool, err error) {
	tx, err := st.DB.BeginTx(ctx, nil)
	if err != nil {
		return false, err
	}
	defer func() {
		if err != nil || !won {
			_ = tx.Rollback()
		}
	}()

	// Step 1: drivers idle -> matched + current_trip_id 設定
	driverWon, err := st.CompareAndSetDriverStatus(ctx, tx,
		driverUserID,
		string(DriverIdle), string(DriverMatched),
		store.SetClause{Column: "current_trip_id", Value: tripID},
	)
	if err != nil {
		return false, err
	}
	if !driverWon {
		return false, nil // driver は他で確定済み
	}

	// Step 2: trips matching -> driver_accepted + driver_id 設定 + matched_at 設定
	tripWon, err := st.CompareAndSetTripStatus(ctx, tx,
		tripID,
		string(TripMatching), string(TripDriverAccepted),
		store.SetClause{Column: "driver_id", Value: driverUserID},
		store.SetClause{Column: "matched_at", Value: sqlNow()},
	)
	if err != nil {
		return false, err
	}
	if !tripWon {
		// trip は他で確定済み (キャンセル等)。driver を idle に戻す。
		// rollback で済むので追加 UPDATE は不要。
		return false, nil
	}

	// Step 3: 監査ログ
	if err = st.InsertTripEvent(ctx, tx, tripID, "accept_committed", &driverUserID, nil); err != nil {
		return false, err
	}

	if err = tx.Commit(); err != nil {
		return false, err
	}
	return true, nil
}

// sqlNow は MySQL CURRENT_TIMESTAMP(6) と同等のリテラルを SET 側へ渡すための raw SQL。
// driver の time.Now() ではなく DB 側の時刻にしたいので *sql.RawBytes は使えず、
// Go 側で time.Now() を採用するか、sql.Expr 相当の機構が要るところだが、
// 本リポでは Go 側時刻で十分 (シングルプロセス想定)。
func sqlNow() any {
	return nowProvider()
}

// nowProvider は test で差し替え可能にするための indirection。
var nowProvider = defaultNow
