# ADR 0004: 認証方式 (JWT bearer / WebSocket query param)

## ステータス

Accepted（2026-05-04）

## コンテキスト

リポジトリ全体方針 (CLAUDE.md) に従い、認証は **最小 1 経路**で十分。OAuth / SSO / 2FA / メール検証は学習対象から除外。

discord プロジェクトは **REST + WebSocket** を持つ。**WebSocket の認証**が REST と異なる扱いになる:

- ブラウザの **WebSocket API は `Authorization` ヘッダを付けられない** (制約)
- `Sec-WebSocket-Protocol` で擬似的に渡す手はあるが server / proxy 側の扱いが面倒
- **`?token=...` query string** が現実的 (Discord 公式 client もこの形)
- ただし URL に token が乗ると **proxy log に残る**ので、production では TLS + log redaction で対処する規律が必要

REST 側はシンプル: `Authorization: Bearer <jwt>`。

他プロジェクトとの対比:

| プロジェクト | 認証 |
| --- | --- |
| slack | rodauth-rails (cookie + ActionCable は cookie 認証) |
| youtube | rodauth-rails (cookie) |
| github | session (X-User-Login fallback dev のみ) |
| perplexity | rodauth-rails JWT bearer (REST + SSE) |
| instagram | DRF TokenAuthentication |
| **discord** | **HS256 JWT bearer (REST + WebSocket)** |

JWT を選ぶことで perplexity と一致するが、**Go 標準の golang-jwt/jwt** で実装するため Ruby gem 経由とは別の体験になる。

## 決定

**「HS256 JWT bearer + WebSocket は `?token=<jwt>` query で受ける」** を採用する。

- **`POST /auth/register`**: `{username, password}` → `{token, user}` 返却 (HS256 JWT, exp 24h)
- **`POST /auth/login`**: 同上、既存 user で token を再発行
- **REST endpoints**: `Authorization: Bearer <jwt>` を `chi` middleware で検証 → `context.Context` に user_id を入れる
- **WebSocket `/gateway`**:
  - 接続時 `?token=<jwt>` を受け取る
  - upgrade 前に検証、無効なら **HTTP 401** (upgrade させない)
  - 検証通過後に upgrade、IDENTIFY で再度 `token` フィールドを受けて二重チェック (man-in-the-middle 対策)
- **password hash**: `bcrypt.DefaultCost` (`golang.org/x/crypto/bcrypt`)
- **JWT signing key**: env `JWT_SECRET` (production は Secrets Manager)
- **claim**: `{sub: user_id, exp, iat}` の最小構成。permissions / role 等は claim に詰めない (DB から都度 lookup)

## 検討した選択肢

### 1. HS256 JWT + WS query param ← 採用

- 利点: REST + WS が同じ token で完結 (perplexity との対比でも有用)
- 利点: stateless、DB lookup が token 検証時のみ (sub の user 存在確認は不要、JWT 自体が認証根拠)
- 利点: `golang-jwt/jwt/v5` がデファクト、Go コミュニティの一般選択
- 欠点: revocation が苦手 (blacklist 不要なら exp で済ます)
- 欠点: URL に token 乗る (WS query) → log に残るリスク

### 2. session cookie

- 利点: ブラウザ標準、自動付与
- 欠点: WS で cookie を読む実装が必要 (chi 経由なら同 origin の cookie は来るが) + CSRF 対策が要る
- 欠点: Go 側に session store (memory / Redis) を持たないといけない、stateless 思想と合わない
- 欠点: SPA + 別 origin (Next.js dev :3055 ↔ Go :3060) で cookie 設定が複雑化

### 3. API token table (DRF 風 / instagram で採用)

- 利点: revocation 容易、DB 側で都度有効性チェック
- 欠点: Go では gem/lib 標準でない、手書きが多い
- 欠点: instagram で同じパターンを学習済み、本プロジェクトでは別経路で学ぶ価値

### 4. OAuth / OIDC

- 利点: production 想定なら必要
- 欠点: スコープ過剰 (CLAUDE.md「認証手段の網羅は除外」に反する)
- 欠点: 外部 IdP 依存 (ローカル完結方針に反する)

### 5. Sec-WebSocket-Protocol で token 渡し

- 利点: URL に token が乗らない
- 欠点: subprotocol 値の format が「カンマ区切りリスト」で **ヘッダで token 渡す idiom が広まっていない**
- 欠点: gorilla/websocket / proxy / browser 各層で扱いがブレる
- 欠点: 学習対象が「認証」ではなく「subprotocol の compatibility」に逸れる

### 6. ws_token を別 endpoint で発行 (短命)

- 利点: 長命の JWT を URL に乗せない
- 欠点: 経路が二重化、本 ADR スコープ超え
- **派生 ADR で扱う余地** (production 想定で「`/auth/ws-ticket` で 60 秒有効の片刀 token を発行」)

## 採用理由

- **学習価値**: Go の `golang-jwt/jwt` + `bcrypt` + `chi middleware` の最短経路。Go server で auth middleware を書く実務感が得られる
- **アーキテクチャ妥当性**: 実 Discord 公式 client も query で token を渡す形 (詳細は非公開だが gateway 接続では URL 経由が知られる)
- **責務分離**: auth middleware を 1 箇所に集約。各 handler は `auth.UserIDFromContext(r.Context())` で user_id を取り出すだけ
- **将来の拡張性**: ws_token (短命 ticket) は派生 ADR で「JWT を URL に乗せない」改良として追加できる

## 却下理由

- **session cookie**: SPA + WS + cross-origin で煩雑、Go の stateless 思想と外れる
- **API token table**: instagram と重複、学習効果薄い
- **OAuth**: スコープ過剰
- **Sec-WebSocket-Protocol**: idiom がブレる、学習対象から逸れる

## 引き受けるトレードオフ

- **revocation 不可**: JWT は exp までは有効。logout は「クライアント側で token 破棄」のみで server 側は何もしない。完全 revocation には blacklist テーブルが要るが派生 ADR
- **URL に token が乗る**: WS query 経由なので proxy log / browser history に残るリスク。production では access log の query string を redaction する規律 (Terraform で CloudWatch log group 側に注記)
- **token TTL = 24h**: rotation / refresh は派生 ADR
- **claim 最小**: permissions を claim に詰めないので、各 handler は DB lookup する。これは intentional (revocation 不能な claim に権限を載せない)
- **password reset / email verification なし**: 1 経路スコープ外
- **WebSocket での token 二重検証**: upgrade 前 (query) + IDENTIFY (body) の 2 回。query だけだと「他人の URL を踏ませる reflection 攻撃」を許す可能性があり、IDENTIFY で再送を要求する規律で安全側

## このADRを守るテスト / 実装ポインタ（Phase 2-3 で実装）

- `discord/backend/internal/auth/jwt.go` — `Sign(userID) string` / `Verify(token) (userID, error)`
- `discord/backend/internal/auth/middleware.go` — chi middleware で `Authorization: Bearer` 検証 + `context.WithValue(r.Context(), userIDKey, id)`
- `discord/backend/internal/auth/handler.go` — `POST /auth/register` / `POST /auth/login`
- `discord/backend/internal/gateway/upgrade.go` — `?token=` 検証 + IDENTIFY 二重検証
- `discord/backend/internal/auth/jwt_test.go` — sign/verify、expired token、tampered token
- `discord/backend/internal/auth/middleware_test.go` — 401 (no header / invalid / expired)
- `discord/backend/internal/gateway/upgrade_test.go` — query 経由認証、IDENTIFY 二重チェック

## 関連 ADR

- ADR 0001: 単一プロセスの REST + WS gateway 同居
- ADR 0002: Hub の goroutine pattern (認証通過後の register 経路)
- ADR 0003: HEARTBEAT (認証通過後の維持機構)
- ADR 0012 (派生予定): ws_token (短命 ticket) で URL に長命 JWT を乗せない改良
- ADR 0013 (派生予定): refresh token rotation
- 関連: `perplexity/docs/adr/0007-auth-rodauth-jwt-bearer.md` — Rails で同役割
- 関連: `instagram/docs/adr/0004-auth-drf-token.md` — Django で同役割
