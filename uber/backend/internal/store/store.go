// Package store は MySQL に対する CRUD と低レベル compare-and-set を集約する責務を持つ。
// 状態遷移ルール (TransitionTrip / TransitionDriver) は internal/dispatch にあり、
// 本パッケージは「primitives」のみを提供する (ADR 0002)。
package store

import (
	"context"
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
	UserID        int64     `json:"user_id"`
	Status        string    `json:"status"`
	CurrentH3Cell *string   `json:"current_h3_cell,omitempty"`
	CurrentLat    *float64  `json:"current_lat,omitempty"`
	CurrentLng    *float64  `json:"current_lng,omitempty"`
	CurrentTripID *int64    `json:"current_trip_id,omitempty"`
	UpdatedAt     time.Time `json:"updated_at"`
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
type TripEvent struct {
	ID          int64     `json:"id"`
	TripID      int64     `json:"trip_id"`
	EventType   string    `json:"event_type"`
	ActorUserID *int64    `json:"actor_user_id,omitempty"`
	PayloadJSON []byte    `json:"payload_json,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
}

type Store struct {
	DB *sql.DB
}

func (s *Store) Ping() error {
	return s.DB.Ping()
}

// ---------- users ----------

// CreateUser は users 行を挿入して新規 ID を返す。email UNIQUE 違反は呼び出し側で MySQL エラーを判別する。
func (s *Store) CreateUser(ctx context.Context, email, passwordHash string, role Role, displayName string) (int64, error) {
	res, err := s.DB.ExecContext(ctx,
		`INSERT INTO users (email, password_hash, role, display_name) VALUES (?, ?, ?, ?)`,
		email, passwordHash, string(role), displayName)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

func (s *Store) UserByID(ctx context.Context, id int64) (*User, error) {
	row := s.DB.QueryRowContext(ctx,
		`SELECT id, email, password_hash, role, display_name, created_at FROM users WHERE id = ?`,
		id)
	return scanUser(row)
}

func (s *Store) UserByEmail(ctx context.Context, email string) (*User, error) {
	row := s.DB.QueryRowContext(ctx,
		`SELECT id, email, password_hash, role, display_name, created_at FROM users WHERE email = ?`,
		email)
	return scanUser(row)
}

func scanUser(row *sql.Row) (*User, error) {
	var u User
	if err := row.Scan(&u.ID, &u.Email, &u.PasswordHash, &u.Role, &u.DisplayName, &u.CreatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &u, nil
}

// ---------- drivers ----------

// CreateDriver は drivers 行を offline 状態で挿入する。
func (s *Store) CreateDriver(ctx context.Context, userID int64) error {
	_, err := s.DB.ExecContext(ctx,
		`INSERT INTO drivers (user_id, status) VALUES (?, 'offline')`,
		userID)
	return err
}

func (s *Store) DriverByUserID(ctx context.Context, userID int64) (*Driver, error) {
	row := s.DB.QueryRowContext(ctx,
		`SELECT user_id, status, current_h3_cell, current_lat, current_lng, current_trip_id, updated_at
		 FROM drivers WHERE user_id = ?`,
		userID)
	var d Driver
	if err := row.Scan(&d.UserID, &d.Status, &d.CurrentH3Cell, &d.CurrentLat, &d.CurrentLng, &d.CurrentTripID, &d.UpdatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &d, nil
}

// UpdateDriverPosition は driver の位置 cell / lat / lng を更新する (位置のみ、status は触らない)。
// MySQL は遅延 mirror、in-memory が真値という ADR 0001 の方針に従う。
func (s *Store) UpdateDriverPosition(ctx context.Context, userID int64, cell string, lat, lng float64) error {
	_, err := s.DB.ExecContext(ctx,
		`UPDATE drivers SET current_h3_cell = ?, current_lat = ?, current_lng = ? WHERE user_id = ?`,
		cell, lat, lng, userID)
	return err
}

// IdleDriversInCells は与えられた cell 群に属する idle driver の user_id を返す (Matcher 用)。
// in-memory index が真値だが、リカバリ用 / 整合性検査用に DB 経由でも引けるようにしておく。
func (s *Store) IdleDriversInCells(ctx context.Context, cells []string) ([]int64, error) {
	if len(cells) == 0 {
		return nil, nil
	}
	q := `SELECT user_id FROM drivers WHERE status = 'idle' AND current_h3_cell IN (?` +
		repeat(",?", len(cells)-1) + `)`
	args := make([]any, len(cells))
	for i, c := range cells {
		args[i] = c
	}
	rows, err := s.DB.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []int64{}
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

func repeat(s string, n int) string {
	if n <= 0 {
		return ""
	}
	out := make([]byte, 0, len(s)*n)
	for i := 0; i < n; i++ {
		out = append(out, s...)
	}
	return string(out)
}

// CompareAndSetDriverStatus は `UPDATE drivers SET status = ? WHERE user_id = ? AND status = ?` の薄ラッパー。
// affected rows が 1 なら遷移成功、0 なら他で確定済み (冪等 no-op 用途)。ADR 0002 の中心パターン。
// extra は同 UPDATE に乗せたい追加列の SET (current_trip_id 設定 / クリアなど) を渡す。
type SetClause struct {
	Column string
	Value  any
}

func (s *Store) CompareAndSetDriverStatus(ctx context.Context, tx *sql.Tx, userID int64, from, to string, extras ...SetClause) (bool, error) {
	q := "UPDATE drivers SET status = ?"
	args := []any{to}
	for _, e := range extras {
		q += ", " + e.Column + " = ?"
		args = append(args, e.Value)
	}
	q += " WHERE user_id = ? AND status = ?"
	args = append(args, userID, from)

	var res sql.Result
	var err error
	if tx != nil {
		res, err = tx.ExecContext(ctx, q, args...)
	} else {
		res, err = s.DB.ExecContext(ctx, q, args...)
	}
	if err != nil {
		return false, err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return false, err
	}
	return n == 1, nil
}

// ---------- trips ----------

func (s *Store) CreateTrip(ctx context.Context, riderID int64, pickupLat, pickupLng float64, pickupCell string, dropoffLat, dropoffLng float64) (int64, error) {
	res, err := s.DB.ExecContext(ctx,
		`INSERT INTO trips (rider_id, status, pickup_lat, pickup_lng, pickup_h3_cell, dropoff_lat, dropoff_lng)
		 VALUES (?, 'requested', ?, ?, ?, ?, ?)`,
		riderID, pickupLat, pickupLng, pickupCell, dropoffLat, dropoffLng)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

func (s *Store) TripByID(ctx context.Context, id int64) (*Trip, error) {
	row := s.DB.QueryRowContext(ctx,
		`SELECT id, rider_id, driver_id, status,
		        pickup_lat, pickup_lng, pickup_h3_cell,
		        dropoff_lat, dropoff_lng,
		        fare_cents, canceled_reason,
		        requested_at, matched_at, completed_at, canceled_at
		 FROM trips WHERE id = ?`, id)
	var t Trip
	if err := row.Scan(&t.ID, &t.RiderID, &t.DriverID, &t.Status,
		&t.PickupLat, &t.PickupLng, &t.PickupH3Cell,
		&t.DropoffLat, &t.DropoffLng,
		&t.FareCents, &t.CanceledReason,
		&t.RequestedAt, &t.MatchedAt, &t.CompletedAt, &t.CanceledAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &t, nil
}

// CompareAndSetTripStatus は trips.status を compare-and-set で進める。
// extras に driver_id / matched_at / completed_at / canceled_at / canceled_reason / fare_cents 等を乗せる。
func (s *Store) CompareAndSetTripStatus(ctx context.Context, tx *sql.Tx, tripID int64, from, to string, extras ...SetClause) (bool, error) {
	q := "UPDATE trips SET status = ?"
	args := []any{to}
	for _, e := range extras {
		q += ", " + e.Column + " = ?"
		args = append(args, e.Value)
	}
	q += " WHERE id = ? AND status = ?"
	args = append(args, tripID, from)

	var res sql.Result
	var err error
	if tx != nil {
		res, err = tx.ExecContext(ctx, q, args...)
	} else {
		res, err = s.DB.ExecContext(ctx, q, args...)
	}
	if err != nil {
		return false, err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return false, err
	}
	return n == 1, nil
}

// ---------- trip_events (append-only) ----------

// InsertTripEvent は trip_events に append する。UPDATE / DELETE 用 method は意図的に生やさない。
func (s *Store) InsertTripEvent(ctx context.Context, tx *sql.Tx, tripID int64, eventType string, actorUserID *int64, payloadJSON []byte) error {
	q := `INSERT INTO trip_events (trip_id, event_type, actor_user_id, payload_json) VALUES (?, ?, ?, ?)`
	args := []any{tripID, eventType, actorUserID, payloadJSON}
	var err error
	if tx != nil {
		_, err = tx.ExecContext(ctx, q, args...)
	} else {
		_, err = s.DB.ExecContext(ctx, q, args...)
	}
	return err
}
