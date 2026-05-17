package dispatch

import "testing"

// TestTripTransitions_ADR0002: ADR 0002 で宣言した遷移と TripTransitions が一致するか。
// 「遷移マップとアプリ層 TRANSITIONS の二重管理」のうちアプリ層側の整合を守る (ADR 0002 §引き受けるトレードオフ)。
func TestTripTransitions_ADR0002(t *testing.T) {
	cases := []struct {
		name string
		from TripStatus
		to   TripStatus
		want bool
	}{
		// 正常系遷移
		{"requested->matching", TripRequested, TripMatching, true},
		{"matching->driver_accepted", TripMatching, TripDriverAccepted, true},
		{"driver_accepted->arriving", TripDriverAccepted, TripArriving, true},
		{"arriving->arrived", TripArriving, TripArrived, true},
		{"arrived->in_trip", TripArrived, TripInTrip, true},
		{"in_trip->completed", TripInTrip, TripCompleted, true},
		// cancel は arrived までの 5 段階で可
		{"requested->canceled", TripRequested, TripCanceled, true},
		{"matching->canceled", TripMatching, TripCanceled, true},
		{"driver_accepted->canceled", TripDriverAccepted, TripCanceled, true},
		{"arriving->canceled", TripArriving, TripCanceled, true},
		{"arrived->canceled", TripArrived, TripCanceled, true},
		{"in_trip->canceled", TripInTrip, TripCanceled, true},
		// terminal からの脱出は無い
		{"completed->canceled (illegal)", TripCompleted, TripCanceled, false},
		{"canceled->completed (illegal)", TripCanceled, TripCompleted, false},
		// 段飛ばし禁止
		{"requested->driver_accepted (illegal skip matching)", TripRequested, TripDriverAccepted, false},
		{"matching->in_trip (illegal skip 3 steps)", TripMatching, TripInTrip, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := IsValidTripTransition(tc.from, tc.to); got != tc.want {
				t.Errorf("IsValidTripTransition(%s, %s) = %v, want %v", tc.from, tc.to, got, tc.want)
			}
		})
	}
}

// TestDriverTransitions_ADR0002: driver 状態遷移、ADR 0002 と一致する。
func TestDriverTransitions_ADR0002(t *testing.T) {
	cases := []struct {
		from DriverStatus
		to   DriverStatus
		want bool
	}{
		// 正常系
		{DriverOffline, DriverIdle, true},
		{DriverIdle, DriverMatched, true},
		{DriverMatched, DriverEnRoutePickup, true},
		{DriverEnRoutePickup, DriverOnTrip, true},
		{DriverOnTrip, DriverIdle, true},
		// cancel での idle 戻り
		{DriverMatched, DriverIdle, true},
		{DriverEnRoutePickup, DriverIdle, true},
		// 飛び越え禁止
		{DriverOffline, DriverMatched, false}, // login 経由必須
		{DriverIdle, DriverOnTrip, false},     // matched 経由必須
		// 逆遷移
		{DriverOnTrip, DriverMatched, false},
	}
	for _, tc := range cases {
		if got := IsValidDriverTransition(tc.from, tc.to); got != tc.want {
			t.Errorf("IsValidDriverTransition(%s, %s) = %v, want %v", tc.from, tc.to, got, tc.want)
		}
	}
}

// TestIsTerminalTrip: terminal は completed と canceled の 2 つだけ。
func TestIsTerminalTrip(t *testing.T) {
	terminal := map[TripStatus]bool{
		TripCompleted: true,
		TripCanceled:  true,
	}
	all := []TripStatus{
		TripRequested, TripMatching, TripDriverAccepted,
		TripArriving, TripArrived, TripInTrip,
		TripCompleted, TripCanceled,
	}
	for _, s := range all {
		want := terminal[s]
		if got := IsTerminalTrip(s); got != want {
			t.Errorf("IsTerminalTrip(%s) = %v, want %v", s, got, want)
		}
	}
}
