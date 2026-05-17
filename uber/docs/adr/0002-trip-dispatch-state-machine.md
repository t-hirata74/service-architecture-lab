# ADR 0002: trip + driver の二者間 state machine、compare-and-set でドライバ取得

## ステータス

Accepted (2026-05-17)

## コンテキスト

配車では **rider と driver の 2 アクター** が一つの trip を介して同時並行に状態を進める。zoom (ADR 0002) や shopify (ADR 0003) で扱った state machine は単一アクター主導 (zoom = host, shopify = system) だが、uber は:

- **rider 側**: 要求 → キャンセル可能
- **driver 側**: offer 受信 → accept → 到着 → 開始 → 完了 (途中で no-show / fault によるキャンセル可能)
- **system 側**: マッチタイムアウト / heartbeat 失効による offline 化

この 3 系統が **同一 trip の status を排他的に進める** ことを保証しなければならない。

加えて、配車固有の競合課題:

1. **二重取得**: 同一 idle ドライバに対して 2 件の trip request matcher が同時に offer を投げ、両方 accept される race
2. **キャンセル後の accept**: rider がキャンセルした直後にドライバが accept する race
3. **at-least-once 通知**: WS 切断→再接続で同じ offer が driver に二度届く可能性、accept が二度実行される race

ローカル完結方針 + MySQL のみ (Redis 不使用) という制約のもとで、これらの race を **DB 制約と compare-and-set** だけで吸収したい。

## 決定

**`trips.status` と `drivers.status` の 2 つの ENUM を持ち、ENUM × 遷移マップで状態を限定。状態遷移は必ず `UPDATE ... WHERE status = '<expected>'` の compare-and-set で実行する。** Affected rows 0 行の場合は「他で確定済み / キャンセル済み」として **冪等 no-op で扱う**。

### Trip status (7 + 2)

```
requested ──► matching ──► driver_accepted ──► arriving ──► arrived ──► in_trip ──► completed
   │            │              │                   │           │           │
   ▼            ▼              ▼                   ▼           ▼           ▼
canceled    canceled       canceled            canceled    canceled   canceled
   │                          (auto by rider / driver / system)
   ▼
no_driver_found  (matcher タイムアウト)
```

- **completed と canceled** は terminal state。`no_driver_found` は canceled のサブカテゴリ (理由列で区別)
- **driver_accepted → arriving** は driver の WS event、`{op: "en_route"}` で遷移
- **arriving → arrived** も driver event、`{op: "arrived"}`
- **arrived → in_trip** は driver の `{op: "start_trip"}` (rider が乗ったタイミング)

### Driver status (5)

```
offline ──► idle ──► matched ──► en_route_pickup ──► on_trip ──► idle
              ▲                                                    │
              └────────── trip cancel / complete ────────────────┘
```

- **matched** = ドライバが offer を accept した直後、まだ移動開始前 (trip = driver_accepted)
- **en_route_pickup** = trip = arriving に同期
- **on_trip** = trip = in_trip に同期
- 直接 `offline → matched` のような遷移は無い (常に idle を経由)

### compare-and-set パターン

**ドライバ accept** (二重取得防止):

```sql
UPDATE drivers
SET status = 'matched', current_trip_id = ?
WHERE user_id = ?
  AND status = 'idle'
LIMIT 1;
-- 0 行更新 → "他で確定済み" を返す (offer 元 matcher へエラー、driver client に "too late")
```

**Trip キャンセル** (accept との race を吸収):

```sql
UPDATE trips
SET status = 'canceled', canceled_reason = 'rider', canceled_at = NOW()
WHERE id = ?
  AND status IN ('requested', 'matching', 'driver_accepted', 'arriving', 'arrived');
-- 0 行更新 → "既に in_trip / completed" を返す
```

**at-least-once accept の冪等吸収**:

`UPDATE drivers SET status='matched' WHERE id=? AND status='idle'` は **同じドライバが同じ trip を二度 accept しても 2 回目は 0 行更新** で吸収される。さらに `trips` テーブルの遷移も同じ guard で守られるので、accept が冪等になる。

### 監査ログ

すべての遷移は `trip_events(trip_id, event_type, payload_json, created_at)` に append-only で記録。`trip_events` には **UPDATE / DELETE を許可しない** (zoom ADR 0002 と同方針)。`updated_at` カラムを持たないことで「追加専用テーブル」のシグナルにする。

## 検討した選択肢

### 1. ENUM × 遷移マップ × compare-and-set ← 採用

- 利点: **DB に状態が落ちている** ので backend 再起動で失われない
- 利点: compare-and-set 1 文で **lock free に race を吸収**
- 利点: ENUM の整合性は MySQL の CHECK 制約 + アプリ層 TRANSITIONS マップで二重防御 (calendly ADR 0003 §23 の SoT 試験と同形)
- 欠点: ENUM 文字列の MySQL 制約とアプリ層 const の二重管理 → calendly で確立した `information_schema.CHECK_CONSTRAINTS` 経由の整合性テストで吸収

### 2. SELECT FOR UPDATE + トランザクション

- 利点: lock を明示的に取れる、複雑な多行更新でも整合性が取りやすい
- 欠点: **lock 待ち deadlock** が発生しやすい (driver と trip の lock 順を厳密に守る必要)
- 欠点: matcher goroutine の per-cell シリアル実行性 (ADR 0003) を活かせない
- 欠点: 学習価値: shopify ADR 0003 で既に "lock free な compare-and-set" を扱ったので、uber でも同じ価値を残す ほうが整合する

### 3. 楽観ロック (version カラム)

- 利点: ORM フレンドリー、ActiveRecord の `lock_version` のような既存パターン
- 欠点: Go では ORM を使わない方針 (discord ADR と同方針)、自前で書くと compare-and-set とほぼ同じ
- 欠点: **複数列の同時更新** (status + driver_id + matched_at) では version 衝突の判定が複雑

### 4. Redis SETNX による分散ロック

- 利点: 高頻度のショート lock に強い
- 欠点: policy 上 Redis を新規導入したくない (discord ADR 0001 と整合)
- 欠点: Redis lock は **TTL 切れによる二重ロック解除** の罠が深い (Redlock 論争)。学習負荷は高いが本プロジェクトの主課題ではない

## 採用理由

- **学習価値**: 「**二者間 + 競合取得 + at-least-once**」を MySQL の compare-and-set だけで解く設計は実プロダクションでも使われる (Uber / Lyft が論文・カンファレンス発表で言及)
- **アーキテクチャ妥当性**: shopify ADR 0003 (在庫の compare-and-decrement) / zoom ADR 0002 (長寿命 state machine) と整合。本リポの **「lock-free 系列」** の延長
- **責務分離**: matcher goroutine (ADR 0003) は **判断だけ**、DB は **状態の永続化 + 競合解決** だけ、と責務が綺麗に切れる
- **将来の拡張性**: 派生 ADR で「キャンセル後の auto re-dispatch」「driver fault detection」「rating loop」を追加できる

## 却下理由

- **SELECT FOR UPDATE**: per-cell goroutine と相性が悪い、deadlock リスク
- **楽観ロック**: Go では ORM を使わないので version 管理が手作業、compare-and-set とほぼ同等になる
- **Redis SETNX**: 新規ミドルウェア導入のコストに見合わない、TTL 罠の学習負荷が主課題から逸れる

## 引き受けるトレードオフ

- **遷移マップとアプリ層 TRANSITIONS の二重管理**: 整合性試験 (`internal/storage/migrations` の SQL CHECK と `internal/dispatch.Transitions` の Go map を比較する unit test) で吸収。calendly §23 と同形
- **0 行更新の意味付け**: 「0 行 = 既に他で確定 = 冪等 no-op で扱う」というルールを **コードコメントで明示**。0 行をエラーにしない実装側の一貫性が要る
- **at-least-once accept の判定窓**: 同じ driver が同じ trip を二度 accept すると 2 回目は 0 行で no-op。ただし `trip_events` には 2 件記録される。**監査では「実際に成立した遷移」と「試みた遷移」を区別**できるよう event_type で区別する (`accept_attempt` / `accept_committed`)
- **キャンセルと accept の真の同時刻**: ms 単位の race は SQL の COMMIT 順で勝者が決まる。それは「最後に COMMIT した側が勝つ」という DB 仕様に委ねる

## このADRを守るテスト / 実装ポインタ

- `uber/backend/internal/dispatch/state.go` — `Transitions` map[TripStatus][]TripStatus
- `uber/backend/internal/dispatch/state_test.go` — `Transitions` と SQL CHECK 制約の整合 (calendly §23 と同形)
- `uber/backend/internal/dispatch/accept_test.go` — `t.Parallel()` で 100 goroutine 同時 accept、勝者 1 / 敗者 99 を検証
- `uber/backend/internal/dispatch/cancel_test.go` — accept と cancel の race で **どちらかが勝ち、両方成功しない** ことを検証
- `uber/backend/internal/storage/migrations/0002_trips.sql` — `status` ENUM と CHECK 制約

## 関連 ADR

- ADR 0001: H3 geospatial index — matcher が cell から候補ドライバを取り出す前提
- ADR 0003: per-cell matcher goroutine — 本 ADR で扱った compare-and-set を実際に呼び出す主体
- ADR 派生候補: キャンセル後の auto re-dispatch / driver no-show による automatic cancel / rating loop
- zoom ADR 0002 (長寿命 state machine) — 単一アクター対比
- shopify ADR 0003 (compare-and-decrement) — lock-free 整合性パターンの参考
