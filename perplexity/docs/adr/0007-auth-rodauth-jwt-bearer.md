# ADR 0007: 認証方式に rodauth-rails + JWT bearer を採用する

## ステータス

Accepted（2026-05-03）

## コンテキスト

Phase 1-4 では暫定的に `X-User-Id` ヘッダで `current_user` を引いていた
（`Rails.env.production?` では reject する production guard 付き）。
Phase 5 でこれを本物の認証経路に置き換える必要がある。

要件:

- Backend は **API モードの Rails 8**（フルスタックではない）
- Frontend は Next.js 16 を **別ポート 3035 でクロスオリジン**
- `GET /queries/:id/stream` は **`ActionController::Live` の SSE long-lived HTTP**。
  認証情報はリクエスト開始時の 1 度だけ確認できればよい
- 認証要件は最小 1 経路（CLAUDE.md 「除外する」に従う）。OAuth / SSO / 2FA は対象外
- Phase 1-4 の RSpec 101 件を破壊しないトランジション戦略が望ましい

## 決定

**rodauth-rails** を採用し、**JSON + JWT** プラグインで Bearer Token 認証を行う。

- ログイン (`POST /login`) 成功時に `Authorization` レスポンスヘッダで JWT を返却
- クライアントは以降のリクエストの `Authorization` ヘッダ（`Bearer ` prefix 任意）に
  JWT を載せる
- accounts と users は **共有 PK** で 1:1 紐付け（slack の ADR 0004 と同パターン）
- JWT secret は `RODAUTH_JWT_SECRET` env → `Rails.application.secret_key_base` の順で
  解決。本番想定では Secrets Manager で配布（`infra/terraform/secrets.tf`）
- **トランジション期間**：`ApplicationController` は
  - `Authorization` ヘッダがあれば rodauth で検証
  - 無ければ `X-User-Id` で fallback（development / test のみ。production は 401）

  これにより既存 RSpec 101 件は無改変で通り続け、新規エンドポイントは JWT を要求できる。
  frontend の login 画面が完成したら fallback を削除する。

## 検討した選択肢

### 1. rodauth-rails + JWT ← 採用

- slack プロジェクト（ADR 0004）と同じパターンで、リポジトリ全体での一貫性が出る
- API モード + クロスオリジン + SSE で扱いやすい（cookie より header 制御が単純）
- メール認証 / パスワードリセット / 2FA / OAuth2 を **公式機能**として後付けできるため、
  将来「最小 1 経路」を超えて拡張する場合の道筋がついている

### 2. rodauth-rails + cookie session

- README で当初想定していた経路だが、API-only Rails + Next.js のクロスオリジン構成では
  `SameSite=None; Secure` + CORS `credentials: include` の設定が増え、
  本質的でない複雑性が上がる
- SSE は long-lived だが認証は接続開始時のみ。cookie の利点（自動付与）を生かしづらい
- 学習価値という観点では JWT bearer のほうが「JWT signing / decode の挙動を直接見られる」
  ぶん本プロジェクトのスコープと噛み合う

### 3. Devise + devise-jwt

- monolithic で機能を取捨選択しづらい
- API + JWT 用途では補助 gem 依存が多く、rodauth に対する優位性が薄い

### 4. Rails 8 標準 `has_secure_password` + 自前 JWT 発行

- 認証コードを自前実装するのは脆弱性混入リスクが高く、学習用途でも避けるべき
- 2FA / OAuth など拡張がすべて自前になり、学習対象がブレる

## 採用理由 / 却下理由

- rodauth-rails が **Rails コミュニティで次世代の本命**として採用が増えており、
  本リポジトリは「**学習価値が高く、実務でも採用が増えている技術**」を優先したい
- slack プロジェクトと同じ選択にすることで、リポジトリ内での **設計判断の一貫性** が取れる
  （言語別バックエンド方針：CLAUDE.md「学習方針」セクション）
- cookie auth ではなく JWT bearer にしたのは、**SSE proxy エンドポイント（ADR 0003）が
  long-lived HTTP**であり、JWT bearer のほうが request 開始時の認証として素直に書けるため

## 引き受けるトレードオフ

- JWT は revoke が難しい。JTI ブラックリスト等を入れる場合は派生 ADR で扱う
- トランジション期の `X-User-Id` fallback は **development / test 限定**だが、
  経路としては残るので production でうっかり有効化されないようテストで縛る
  （`spec/requests/auth_rodauth_spec.rb` で `production` env での 401 を将来追加する）
- frontend 側に **login 画面の UI 実装**が別途必要。Phase 5 ではバックエンド経路と
  api.ts の Authorization ヘッダ送信のみ追加し、login 画面は派生タスクで扱う
