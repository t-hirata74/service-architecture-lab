# Mock 3rd-party App receiver

ADR 0004 (Webhook 配信) のローカル受信モック。Rails backend (`shopify/backend`) が
Solid Queue 経由で配信する webhook を受け取り、HMAC 検証 + delivery_id 冪等チェックを
行ったうえで in-memory に保持し、`/` の Web UI に 1 秒間隔で表示する。

playwright での gif 生成 (`shopify/playwright`) はこの UI を 2 つ目の context として
ストアフロントの checkout と並べて録画する。

## 起動

```bash
bundle install
DEMO_APP_SECRET=demo-shared-secret-do-not-use-in-prod bundle exec ruby app.rb -p 4000
# → http://localhost:4000
```

`DEMO_APP_SECRET` は `backend/db/seeds.rb` で `Apps::App#secret` に投入されるものと
合わせる必要がある (`Apps::Signer` が同じ secret で HMAC を生成するため)。

## エンドポイント

| path | 役割 |
| --- | --- |
| `POST /webhooks/shopify` | Rails からの配信先。`X-Hmac-Sha256` `X-Webhook-Delivery-Id` `X-Webhook-Topic` を読む。HMAC 不一致は 401。 |
| `GET /api/deliveries` | UI からの polling 用。直近 50 件を JSON で返す。 |
| `POST /api/reset` | デモ前に履歴をクリア。 |
| `GET /` | 受信ログを表示する HTML。1s polling。 |

## 不変条件

1. **HMAC 検証**: `X-Hmac-Sha256== HMAC_SHA256(secret, raw body)` を
   `Rack::Utils.secure_compare` で照合。失敗したら 401 を返し、Rails 側は retry を継続する。
2. **冪等性 (delivery_id)**: 同じ `X-Webhook-Delivery-Id` は再受信扱いとして UI 上に
   `duplicate` バッジを出す (本番アプリならここで処理を skip するイメージ)。
