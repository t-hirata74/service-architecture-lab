// Package ws は driver の WebSocket gateway (offer 配信 + position 更新 + accept/reject)。
//
// rider 側 (trip status の push 通知) は本 Phase ではスコープ外。rider は GET /trips/:id で poll する。
package ws

// Op codes for client→server and server→client.
type Op string

const (
	// client → server
	OpGoOnline  Op = "go_online"  // {op, lat, lng}
	OpPosition  Op = "position"   // {op, lat, lng}
	OpAccept    Op = "accept"     // {op, trip_id}
	OpReject    Op = "reject"     // {op, trip_id}
	OpGoOffline Op = "go_offline" // {op}

	// server → client
	OpOffer Op = "offer" // {op, trip_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, expires_at}
	OpError Op = "error" // {op, message}
	OpHello Op = "hello" // {op, user_id, role}
)

// Inbound は client → server の通称用 union。各 op で必要なフィールドだけが入る。
type Inbound struct {
	Op     Op      `json:"op"`
	Lat    float64 `json:"lat,omitempty"`
	Lng    float64 `json:"lng,omitempty"`
	TripID int64   `json:"trip_id,omitempty"`
}

// Outbound は server → client。client 側パーサ簡易化のため、すべての op で同形を返す。
type Outbound struct {
	Op         Op      `json:"op"`
	UserID     int64   `json:"user_id,omitempty"`
	Role       string  `json:"role,omitempty"`
	Message    string  `json:"message,omitempty"`
	TripID     int64   `json:"trip_id,omitempty"`
	PickupLat  float64 `json:"pickup_lat,omitempty"`
	PickupLng  float64 `json:"pickup_lng,omitempty"`
	DropoffLat float64 `json:"dropoff_lat,omitempty"`
	DropoffLng float64 `json:"dropoff_lng,omitempty"`
	ExpiresAt  string  `json:"expires_at,omitempty"`
}
