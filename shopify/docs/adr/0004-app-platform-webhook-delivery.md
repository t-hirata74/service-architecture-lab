# ADR 0004: App プラットフォーム — Webhook 配信 (at-least-once + HMAC + idempotency)

## ステータス

Accepted（2026-05-04）

## コンテキスト

Shopify を Shopify たらしめている特徴の 1 つが「**App プラットフォーム**」、すなわちサードパーティが Shop の lifecycle イベント（注文、在庫変動など）を webhook で受信し、認証された API で書き戻せる仕組み。本プロジェクトでは、その**配信側 (publisher) の設計**を最小モックで再現する。

技術論点：
- App は複数 Shop に install される（M:N、`AppInstallation` が結節）
- Shop で発生したイベント（`order.created`, `inventory.updated`）を、各 install されたアプリの subscriber に **at-least-once** で配信する
- 受信側が再起動 / ネットワーク障害で受け取れない場合の **retry**（exponential backoff）
- 改ざん防止のための **HMAC 署名** ヘッダ（実 Shopify と同じく `X-Shopify-Hmac-Sha256` 風）
- 受信側の冪等性のための **idempotency-key**（`X-Webhook-Delivery-Id`）

スコープ外（明示的に切り出し）：
- OAuth フルフロー（mock のみ。`AppInstallation` 作成時に scope 文字列を bind する程度）
- 順序保証（at-least-once + 順序保証は別 ADR）
- App の課金 API、レビュー、Marketplace UI

## 決定

**Solid Queue による at-least-once 配信 + HMAC 署名 + delivery_id idempotency** を採用する。

- イベント発行：`Inventory::DeductService` 等の Service Object が `Apps::EventBus.publish(:inventory_updated, payload, shop:)` を呼ぶ
- `EventBus` は `WebhookSubscription.where(shop:, topic: :inventory_updated)` を引き、`WebhookDelivery` を作成 + Solid Queue に enqueue（**同一トランザクション**で）
- ワーカー (`Apps::DeliveryJob`) が `WebhookDelivery#endpoint` に POST。失敗時は exponential backoff で `max_attempts: 8` まで retry
- POST には `X-Shopify-Hmac-Sha256: base64(hmac(secret, body))` と `X-Webhook-Delivery-Id: <uuid>` を付与
- 受信側はモック App (本リポ内に `apps/mock_receiver` として `sinatra` か小さい Rack app) を 1 つ用意し、署名検証 + delivery_id で冪等処理する例を残す
- `App` の API トークンは scope 文字列 (`read_orders`, `write_inventory`) を持ち、`AppController#authorize_scope!` で per-action 検証

## 検討した選択肢

### 1. Solid Queue + DB-backed delivery 状態 ← 採用

- 利点：本リポの「Redis 不使用 / Solid Queue 採用」と整合（youtube ADR と同じ）
- 利点：`WebhookDelivery` のステータス（pending / delivered / failed_permanent）が DB から見えるので運用観察しやすい

### 2. ActiveJob + DB-backed (Sidekiq / Sucker Punch)

- 利点：選択肢が広い
- 欠点：本リポでは Solid Queue を **Rails 8 標準スタック**として一貫採用している（youtube ADR）

### 3. 同期 webhook 配信（controller から直接 POST）

- 利点：実装がシンプル
- 欠点：受信側の遅延・障害が publisher 側のレスポンスに伝播。**at-least-once / retry / 失敗の隔離**という webhook 設計の本論点が消える

### 4. GraphQL Subscription / WebSocket push のみ

- 利点：streaming で即時
- 欠点：app プラットフォームの実態（HTTP webhook + 受信側が独自 endpoint を持つ）と乖離

### 5. Kafka / NATS のような外部 broker

- 利点：fan-out スケール
- 欠点：ローカル完結方針に反する

## 採用理由

- **学習価値**：webhook 配信の典型論点（at-least-once / 署名 / 冪等性 / retry / poison message）を 1 プロジェクトで全部触れる。本リポの `slack` (WebSocket) / `instagram` (Celery) / `reddit` (APScheduler) との **配信プリミティブの対比**が成立する
- **アーキテクチャ妥当性**：Shopify / Stripe / GitHub の webhook は本質的に同じパターン。本実装は MVP ながら学習資産として転用可能
- **責務分離**：`Apps` Engine が単独で publisher 責務を持ち、他 Engine は `EventBus.publish(...)` のみを知る
- **将来の拡張性**：受信側の rate limit / circuit breaker、配信順序保証、イベントリプレイ API は派生 ADR で扱える土台になる

## 却下理由

- **同期配信**：webhook 設計の本論点（隔離 / retry）を消す
- **外部 broker**：ローカル完結原則に反する。Solid Queue で十分代替できる

## 引き受けるトレードオフ

- **at-least-once → 受信側の冪等性が必須**：これは webhook 設計の必然。`X-Webhook-Delivery-Id` を発行し、モック receiver に「過去 1h の delivery_id を覚える」実装例を置く
- **順序保証なし**：`order.created` と `order.paid` が逆順に届く可能性。Shopify 自身も「順序保証はしない」スタンス。順序が必要な app は `created_at` で並べ替えるか、状態を `GET` で fetch する責務が受信側にある（**派生 ADR 候補**）
- **HMAC 鍵の rotation なし**：MVP は単一 secret。rotation は派生 ADR
- **失敗の永続化**：`max_attempts` 到達後は `WebhookDelivery#status = 'failed_permanent'`。Shopify は app 側の管理画面で失敗 delivery を再送できる UI を持つが、本実装では DB 直叩きの管理コマンドのみ
- **`Apps::EventBus.publish` の失敗が caller (checkout) を rollback させる**：`ActiveSupport::Notifications.instrument("orders.order_created", ...)` の subscriber は同期実行され、subscriber 内で raise すると instrument の caller (Orders::CheckoutService の transaction) に伝搬する。すなわち WebhookDelivery 行の DB エラーや subscription テーブル障害で **checkout 全体が失敗する**。これは「webhook を確実に予約できないなら注文も受けない」という強い at-least-once 保証の代償であり意図通り。代替案 (subscriber を `rescue` して log のみ) は at-least-once 保証を弱めるので採らない。webhook 機能の停止が business critical な checkout を止めることを防ぎたい場合は、kill switch (subscription 自体を全件 disable する運用フラグ) を派生 ADR で
- **Webhook receiver の SSRF 危険性**：`WebhookSubscription#endpoint` に任意 URL を保存できる構造。`http://169.254.169.254/` (AWS metadata) や `http://localhost:*/` などの内部資源を叩かせる SSRF が可能。MVP / ローカル方針では許容するが、**production 化する場合は IP allowlist / DNS resolve restriction (private IP 拒否) を必ず入れる** (派生 ADR)
- **`Apps::App.secret` の平文保存**：HMAC 鍵を平文で保存。rotation がない前提なら encryption-at-rest (Rails 7+ の `encrypts :secret`) を導入すべきだが、MVP は許容。production 化時に encryption を入れる (派生 ADR)
- **Solid Queue worker の常駐が前提**：`bin/jobs` を別プロセスで常駐させないと DeliveryJob が dispatch されない。Rails app 側だけ起動してジョブが「pending のまま戻ってこない」状態を生まないため、README に起動手順を明記する

## このADRを守るテスト / 実装ポインタ

- `spec/apps/webhook_delivery_spec.rb` — 受信側 500 → retry → 成功時に `delivered_at` が立つこと、`max_attempts` 後に `failed_permanent`
- `spec/apps/hmac_signature_spec.rb` — 署名一致、tampered body で不一致
- `spec/apps/idempotency_spec.rb` — 同一 `delivery_id` で 2 回受信した時、receiver が 1 回だけ副作用を実行
- `components/apps/app/services/apps/event_bus.rb` — publish 入口
- `components/apps/app/jobs/apps/delivery_job.rb` — Solid Queue worker、backoff 計算

## 関連 ADR

- ADR 0001: モジュラーモノリス（apps Engine の責務範囲）
- ADR 0003: 在庫減算（inventory イベントの publisher）
- 派生候補：Webhook の順序保証、HMAC 鍵 rotation、failed delivery の管理画面、receiver 側 rate limit
