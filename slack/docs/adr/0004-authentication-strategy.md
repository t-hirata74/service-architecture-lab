# ADR 0004: 認証方式に rodauth-rails + JWT を採用する

## ステータス

Accepted（2026-04-30）

## コンテキスト

Slack 風プロジェクトでは以下の認証要件を満たす必要がある：

- Backend は Rails 8 の **API モード**（フルスタックではない）
- Frontend は Next.js を別ポート（3001）で動作させるため **クロスオリジン**
- ActionCable の WebSocket 接続でも同じ認証を使い回せる必要がある
- 将来的に OAuth / メール認証 / 2FA を学習対象として扱える拡張余地が欲しい

加えて、本リポジトリの趣旨上「学習価値が高く、実務でも採用が増えている技術」を優先したい。

## 決定

**rodauth-rails** を採用し、**JSON + JWT** プラグインで Bearer Token 認証を行う。

- ログイン成功時に JWT を返却
- クライアントは `Authorization: Bearer <token>` で認証
- ActionCable 接続時もクエリ string ないしカスタムヘッダで JWT を渡し、`ApplicationCable::Connection#connect` で検証
- リフレッシュトークン機構は rodauth の `jwt_refresh` 機能を利用

## 検討した選択肢

### 1. rodauth-rails + JWT ← 採用

- Roda 製の認証フレームワーク。**機能が module 化**されており、必要な認証機能を機能単位で組み合わせる設計
- API モードでも素直に動作する（`json: true` モード）
- メール認証 / パスワードリセット / 2FA / WebAuthn / OAuth2 まで**全て公式機能**としてカバー
- 実務での採用が増えており、**Rails 界隈で次世代の本命**と目されている
- 学習対象として旨味が大きい

### 2. Devise + devise-jwt

- Rails 認証のデファクト
- ただし **monolithic な設計**で、機能を取捨選択しづらい
- Warden に密結合しており、API モード + JWT の組み合わせは公式サポートが薄く、`devise-jwt` 等の補助 gem が必要
- 学習価値は高いが「もう一度同じものを作るなら何を使うか」を考えると優位性が薄い

### 3. Rails 8 標準 `has_secure_password` 自前実装

- 最小コードで動く
- ただし「**認証は自前実装すべきでない**」という業界常識に反する。学習用途でも、自分で書いた認証コードに脆弱性が残る危険がある
- 2FA / OAuth など拡張が全部自前になり、学習対象がブレる

### 4. セッション Cookie + クロスオリジン設定（rodauth）

- WebSocket 含めてクッキーで通せばシンプル
- ただし **SameSite=None + Secure** が必要 → ローカル開発で HTTPS が要る
- クロスオリジンクッキーはブラウザのプライバシー強化で挙動が変わりやすく、ハマりどころが多い
- API + JWT のほうが「外部クライアントから叩かれる API」の学習として自然

## 採用理由

- **学習価値**：rodauth-rails は使ったことがなく、本リポジトリの「学習目的」と合致
- **拡張性**：OAuth / 2FA / WebAuthn まで公式機能で揃っており、将来の ADR で機能追加判断ができる
- **API モードとの相性**：JSON + JWT モードが第一級でサポートされている
- **WebSocket 認証との一貫性**：JWT を ActionCable の接続検証にも流用できる
- **クロスオリジン問題の回避**：JWT を Authorization ヘッダで渡すことで、SameSite Cookie 問題を回避

## 却下理由

- **Devise**：実務で広く使われているが、本プロジェクトの「学習価値」「拡張性」観点では rodauth に劣る
- **has_secure_password 自前**：認証は自前実装すべきでない原則に反する
- **セッション Cookie**：クロスオリジン HTTPS の煩雑さを学習対象に入れると主目的が散らかる

## 引き受けるトレードオフ

- **rodauth の学習コスト**：Rails 標準の "規約" から外れた Roda 流の DSL に慣れる必要がある。学習目的なのでむしろ歓迎
- **JWT の運用知見が必要**：トークン無効化（ログアウト）は JWT の弱点。rodauth-rails は `account_active_session_keys` を提供しているが、内部は DB ベースのセッションキー検証であり、純粋な stateless JWT ではない
- **Rails コミュニティでの情報量が Devise より少ない**：トラブルシュート時に英語圏の rodauth コミュニティを参照する必要がある
- **デザインがプロジェクトに刺さるかは未知**：使ったことがない技術なので、実装途中で「合わない」と判断したら ADR を Superseded にして Devise に戻す選択肢を残す

## 関連 ADR

- ADR 0001: リアルタイム配信方式（ActionCable + Redis Pub/Sub）→ JWT を ActionCable 認証にも流用
- ADR 0005（予定）: チャンネル / DM の権限モデル

## 参考

- rodauth-rails: https://github.com/janko/rodauth-rails
- rodauth 公式: https://rodauth.jeremyevans.net/
