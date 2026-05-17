// Package store は MySQL に対する CRUD と compare-and-set 操作を集約する責務を持つ。
// 状態遷移ルール (TripStatus / DriverStatus の遷移マップ) は internal/dispatch にあり、
// 本パッケージは「状態を読み書きする」責務だけを引き受ける (ADR 0002)。
package store

import (
	"database/sql"
	"errors"
	"time"
)

var ErrNotFound = errors.New("store: not found")

type Role string

const (
	RoleRider  Role = "rider"
	RoleDriver Role = "driver"
)

type User struct {
	ID           int64     `json:"id"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"-"`
	Role         Role      `json:"role"`
	DisplayName  string    `json:"display_name"`
	CreatedAt    time.Time `json:"created_at"`
}

type Driver struct {
	UserID         int64     `json:"user_id"`
	Status         string    `json:"status"`
	CurrentH3Cell  *string   `json:"current_h3_cell,omitempty"`
	CurrentLat     *float64  `json:"current_lat,omitempty"`
	CurrentLng     *float64  `json:"current_lng,omitempty"`
	CurrentTripID  *int64    `json:"current_trip_id,omitempty"`
	UpdatedAt      time.Time `json:"updated_at"`
}

type Trip struct {
	ID             int64      `json:"id"`
	RiderID        int64      `json:"rider_id"`
	DriverID       *int64     `json:"driver_id,omitempty"`
	Status         string     `json:"status"`
	PickupLat      float64    `json:"pickup_lat"`
	PickupLng      float64    `json:"pickup_lng"`
	PickupH3Cell   string     `json:"pickup_h3_cell"`
	DropoffLat     float64    `json:"dropoff_lat"`
	DropoffLng     float64    `json:"dropoff_lng"`
	FareCents      *int       `json:"fare_cents,omitempty"`
	CanceledReason *string    `json:"canceled_reason,omitempty"`
	RequestedAt    time.Time  `json:"requested_at"`
	MatchedAt      *time.Time `json:"matched_at,omitempty"`
	CompletedAt    *time.Time `json:"completed_at,omitempty"`
	CanceledAt     *time.Time `json:"canceled_at,omitempty"`
}

// TripEvent は trip_events テーブルへの append-only 監査ログ。
// アプリ層から UPDATE / DELETE は行わない (Store にメソッドを生やさない)。
type TripEvent struct {
	ID           int64     `json:"id"`
	TripID       int64     `json:"trip_id"`
	EventType    string    `json:"event_type"`
	ActorUserID  *int64    `json:"actor_user_id,omitempty"`
	PayloadJSON  []byte    `json:"payload_json,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
}

// Store は MySQL コネクションを保持する。実 CRUD メソッドは Phase 3 で追加していく。
// Phase 2 では DB 接続の存在確認 (Ping) のみ。
type Store struct {
	DB *sql.DB
}

func (s *Store) Ping() error {
	return s.DB.Ping()
}
