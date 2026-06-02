# uber アーキテクチャ

> 🟢 Phase 4-1 完了 / backend MVP 動作。本ドキュメントのドメイン境界・データモデル・主要フローは backend 実装 (`internal/{api,ws,dispatch,store,geo,auth}`) と対応する。frontend / ai-worker は Phase 4-2 / Phase 5 で追記する。

## ドメイン境界

- **rider**: trip を要求し、driver が来るまで待つアクター
- **driver**: idle 状態で WS 接続中、offer を受けたら accept/reject、accept 後は en_route_pickup → on_trip → idle に戻る
- **trip**: 二者を結びつける長寿命エンティティ。1 trip = 1 state machine
- **dispatch (Go process 内)**: H3 cell ごとの matcher goroutine + driver position の in-memory store

外部依存:
- MySQL 8 (永続化、Solid Queue 不使用)
- ai-worker (ETA mock / 需要予測 mock)

## データモデル

> 最終形は [`backend/migrations/001_init.up.sql`](../backend/migrations/001_init.up.sql) が正 (canceled_reason / current_trip_id / pickup_h3_cell / trip_events.event_type 11 種 などはそちらを参照)。以下は概要。

- `users(id, role enum(rider,driver), email, password_hash, ...)`
- `drivers(user_id PK, status enum(offline,idle,matched,en_route_pickup,on_trip), current_h3_cell varchar(16), current_lat, current_lng, updated_at)`
- `trips(id, rider_id, driver_id NULL, status enum(...), pickup_lat/lng, dropoff_lat/lng, requested_at, matched_at, completed_at, fare_cents)`
- `trip_events(id, trip_id, event_type, payload_json, created_at)` — append-only 監査

設計メモ:
- `drivers.status` の遷移は **compare-and-set** で守る (ADR 0002)
- `drivers.current_h3_cell` を index 化、ただし position 更新は **in-memory 優先**で DB は eventually consistent (ADR 0001)

## 主要フロー

### 1. Rider が trip を要求

```
1. POST /trips        rider_id, pickup_lat/lng, dropoff_lat/lng
2. backend            H3 cell 計算 → trip(status=requested) を INSERT
3. backend            cell の matcher channel に trip_id を送信
4. matcher goroutine  cell + 1-ring から idle driver を pick → offer channel に送信
5. driver WS          { "op": "offer", "trip_id": ... } 受信
6. driver WS          { "op": "accept", "trip_id": ... }
7. backend            UPDATE drivers SET status='matched' WHERE user_id=? AND status='idle' → 1 行更新
                      UPDATE trips SET driver_id=?, status='driver_accepted'
8. rider WS push      { "op": "matched", "driver_id": ... }
```

### 2. 走行中 / 完了

```
9.  driver WS          { "op": "arrived" } → trips.status='arrived'
10. driver WS          { "op": "start_trip" } → trips.status='in_trip', drivers.status='on_trip'
11. driver WS          { "op": "complete", "actual_distance", "actual_time" }
                      → trips.status='completed', drivers.status='idle', fare 計算
12. rider WS push      { "op": "completed", "fare_cents": ... }
```

### 3. キャンセル (rider 主導 / matcher タイムアウト / driver 主導)

```
- rider が status=matching|driver_accepted|arriving|arrived のとき POST /trips/:id/cancel
- backend  trips.status='canceled', drivers.status='idle' (compare-and-set)
- driver WS push  { "op": "canceled" }
```

詳細な遷移網羅は [ADR 0002](adr/0002-trip-dispatch-state-machine.md)。

## 失敗時の挙動

- **matcher がドライバを見つけられない**: 30s タイムアウトで trip.status='canceled', reason='no_driver'
- **driver が offer を受けたが応答なし**: 10s で matcher が次の候補に進む (driver の status は変更しない)
- **同一 driver に複数 offer**: compare-and-set で 1 件だけ通る、残りは「他で確定済み」を rider に返す
- **driver の WS 切断**: heartbeat (discord ADR 0003 と同形) で 30s 無音→ status=offline、進行中の trip は別途 cleanup ジョブ
- **at-least-once 通知**: trip 完了通知はクライアントの ack 待ち + リトライ。冪等は `trip_id + state` の組で判定

## ローカル運用

- `make uber-deps-up` で MySQL 起動
- `make uber-migrate` で migrations 適用
- `make uber-backend` で `go run ./cmd/dispatch` (REST + /ws + matcher / 実装済み)
- `make uber-frontend` で `npm run dev` (Phase 5 で実装)
- `make uber-ai` で `uvicorn app.main:app --port 8100` (Phase 4-2 で実装)

ports は [README](../README.md#ポート割り当て) 参照。
