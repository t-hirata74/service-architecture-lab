// Package dispatch は trip / driver の state machine 定義を保持する (ADR 0002)。
//
// Phase 2 の責務:
//   - Status 型と Transitions マップを純粋関数 (DB 無し) で定義
//   - IsValidTransition で「遷移が許可されているか」だけを判定
//
// Phase 3 以降の責務 (本ファイルでは扱わない):
//   - DB compare-and-set 実装 (`UPDATE ... WHERE status = '<expected>'`)
//   - matcher goroutine (ADR 0003) との結合
//   - trip_events への append (監査ログ)
package dispatch

// TripStatus は trip の 7 状態 (ADR 0002)。
type TripStatus string

const (
	TripRequested      TripStatus = "requested"
	TripMatching       TripStatus = "matching"
	TripDriverAccepted TripStatus = "driver_accepted"
	TripArriving       TripStatus = "arriving"
	TripArrived        TripStatus = "arrived"
	TripInTrip         TripStatus = "in_trip"
	TripCompleted      TripStatus = "completed"
	TripCanceled       TripStatus = "canceled"
)

// DriverStatus は driver の 5 状態 (ADR 0002)。
type DriverStatus string

const (
	DriverOffline        DriverStatus = "offline"
	DriverIdle           DriverStatus = "idle"
	DriverMatched        DriverStatus = "matched"
	DriverEnRoutePickup  DriverStatus = "en_route_pickup"
	DriverOnTrip         DriverStatus = "on_trip"
)

// TripTransitions は許可された trip 状態遷移。
// 値の slice が空 = terminal state (completed / canceled)。
// ADR 0002 の状態図と一致させる。SQL CHECK 制約との整合は state_test.go で守る。
var TripTransitions = map[TripStatus][]TripStatus{
	TripRequested:      {TripMatching, TripCanceled},
	TripMatching:       {TripDriverAccepted, TripCanceled},
	TripDriverAccepted: {TripArriving, TripCanceled},
	TripArriving:       {TripArrived, TripCanceled},
	TripArrived:        {TripInTrip, TripCanceled},
	TripInTrip:         {TripCompleted, TripCanceled},
	TripCompleted:      {},
	TripCanceled:       {},
}

// DriverTransitions は driver 状態遷移。
// offline → idle (login) / idle → matched (accept) / on_trip → idle (complete) など。
// 直接 offline → matched のような飛び越え遷移は無い (常に idle 経由)。
var DriverTransitions = map[DriverStatus][]DriverStatus{
	DriverOffline:       {DriverIdle},
	DriverIdle:          {DriverOffline, DriverMatched},
	DriverMatched:       {DriverEnRoutePickup, DriverIdle}, // idle 戻りはキャンセル時
	DriverEnRoutePickup: {DriverOnTrip, DriverIdle},        // idle 戻りはキャンセル時
	DriverOnTrip:        {DriverIdle},
}

// IsValidTripTransition は from -> to が TripTransitions で許可されているかを返す。
func IsValidTripTransition(from, to TripStatus) bool {
	for _, allowed := range TripTransitions[from] {
		if allowed == to {
			return true
		}
	}
	return false
}

// IsValidDriverTransition は from -> to が DriverTransitions で許可されているかを返す。
func IsValidDriverTransition(from, to DriverStatus) bool {
	for _, allowed := range DriverTransitions[from] {
		if allowed == to {
			return true
		}
	}
	return false
}

// IsTerminalTrip は trip が terminal (completed / canceled) かを返す。
func IsTerminalTrip(s TripStatus) bool {
	return len(TripTransitions[s]) == 0
}
