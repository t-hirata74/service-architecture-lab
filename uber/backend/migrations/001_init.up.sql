-- users: rider と driver の共通アカウント基盤。role 列で区別。
CREATE TABLE users (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  email VARCHAR(255) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  role ENUM('rider', 'driver') NOT NULL,
  display_name VARCHAR(255) NOT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
);

-- drivers: user_id を PK にした 1:1 拡張。status は ADR 0002 の 5 状態 ENUM。
-- current_h3_cell は ADR 0001 の geospatial index (MySQL 側は遅延 mirror)。
CREATE TABLE drivers (
  user_id BIGINT NOT NULL PRIMARY KEY,
  status ENUM('offline', 'idle', 'matched', 'en_route_pickup', 'on_trip') NOT NULL DEFAULT 'offline',
  current_h3_cell VARCHAR(16) DEFAULT NULL,
  current_lat DECIMAL(10, 7) DEFAULT NULL,
  current_lng DECIMAL(10, 7) DEFAULT NULL,
  current_trip_id BIGINT DEFAULT NULL,
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_drivers_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
  INDEX idx_drivers_cell_status (current_h3_cell, status)
);

-- trips: 二者 (rider + driver) を結びつける長寿命エンティティ。
-- status は ADR 0002 の 7 状態 ENUM。canceled_reason は cancel 時のみ NOT NULL。
CREATE TABLE trips (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  rider_id BIGINT NOT NULL,
  driver_id BIGINT DEFAULT NULL,
  status ENUM(
    'requested',
    'matching',
    'driver_accepted',
    'arriving',
    'arrived',
    'in_trip',
    'completed',
    'canceled'
  ) NOT NULL DEFAULT 'requested',
  pickup_lat DECIMAL(10, 7) NOT NULL,
  pickup_lng DECIMAL(10, 7) NOT NULL,
  pickup_h3_cell VARCHAR(16) NOT NULL,
  dropoff_lat DECIMAL(10, 7) NOT NULL,
  dropoff_lng DECIMAL(10, 7) NOT NULL,
  fare_cents INT DEFAULT NULL,
  canceled_reason ENUM('rider', 'driver', 'no_driver_found', 'system') DEFAULT NULL,
  requested_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  matched_at DATETIME(6) DEFAULT NULL,
  completed_at DATETIME(6) DEFAULT NULL,
  canceled_at DATETIME(6) DEFAULT NULL,
  CONSTRAINT fk_trips_rider FOREIGN KEY (rider_id) REFERENCES users (id),
  CONSTRAINT fk_trips_driver FOREIGN KEY (driver_id) REFERENCES users (id),
  INDEX idx_trips_status_requested (status, requested_at),
  INDEX idx_trips_rider (rider_id, requested_at DESC),
  INDEX idx_trips_driver (driver_id, requested_at DESC),
  INDEX idx_trips_pickup_cell (pickup_h3_cell)
);

-- trip_events: 状態遷移の append-only 監査ログ (zoom HostTransfer / shopify StockMovement と同方針)。
-- updated_at を持たない = "追加専用テーブル" のシグナル。
-- アプリ層では UPDATE / DELETE を発行しない (Store メソッドに INSERT のみ用意)。
CREATE TABLE trip_events (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  trip_id BIGINT NOT NULL,
  event_type ENUM(
    'requested',
    'matching_started',
    'offer_sent',
    'accept_attempt',
    'accept_committed',
    'accept_lost',
    'arriving',
    'arrived',
    'trip_started',
    'completed',
    'canceled'
  ) NOT NULL,
  actor_user_id BIGINT DEFAULT NULL,
  payload_json JSON DEFAULT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  CONSTRAINT fk_trip_events_trip FOREIGN KEY (trip_id) REFERENCES trips (id) ON DELETE CASCADE,
  INDEX idx_trip_events_trip_created (trip_id, created_at)
);
