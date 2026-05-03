# ADR 0004: 認証方式 (DRF TokenAuthentication / 1 経路)

## ステータス

Accepted（2026-05-03）

## コンテキスト

リポジトリ全体方針 (CLAUDE.md) の通り、**認証は最小 1 経路で十分**。OAuth / SSO / 2FA / メール検証は学習対象から意図的に除外する。

`slack` / `youtube` / `github` / `perplexity` プロジェクトは **rodauth-rails (cookie / JWT bearer)** を採用したが、本プロジェクトは **Django/DRF**。Django には Rails の rodauth に直接対応する gem は無く、選択肢は以下:

- Django 標準 SessionAuthentication (cookie + CSRF)
- DRF TokenAuthentication (`Authorization: Token <token>` ヘッダ)
- `djangorestframework-simplejwt` (JWT)
- `django-allauth` (rodauth 相当の多機能 / OAuth 含む)

制約:

- ローカル完結 (外部 IdP / OAuth provider は使わない)
- 1 経路だけ整備し、CRUD / timeline / follow をすべてその 1 経路で保護
- フロント (Next.js 16 / React 19) からの fetch で扱いやすい
- CSRF を扱わずに済むのが望ましい (SPA 化と相性が悪い)
- 学習対象は **「1 経路を選んだ理由 / 他を捨てた理由」** を残すこと

## 決定

**「DRF の `TokenAuthentication` を採用、`Authorization: Token <token>` ヘッダで全 API を保護する」** を採用する。

- **`/auth/register`**: username / password で `User` を作成し、`Token` を発行して返す
- **`/auth/login`**: username / password を受け取り、`Token.objects.get_or_create(user=user)` で token を返す
- **`/auth/logout`**: 受け取った token を delete (再ログインで再発行)
- **`Authorization: Token <token>`** ヘッダで `Post` / `Follow` / `Timeline` / `Like` / `Comment` の全 endpoint を保護
- **CSRF 不要**: TokenAuthentication は SessionAuthentication と異なり CSRF を要求しない
- **frontend は token を `localStorage` に保持**: fetch に `Authorization` ヘッダを付与
- **token 失効 (TTL) は本 ADR スコープ外**: rotation / refresh は派生 ADR で扱う余地として残す
- **password ハッシュは Django 標準の PBKDF2 (`set_password()`)**: 自前実装しない

## 検討した選択肢

### 1. DRF TokenAuthentication ← 採用

- 利点: DRF 標準。`rest_framework.authtoken` を `INSTALLED_APPS` に追加するだけで使える
- 利点: CSRF 不要、SPA との相性が良い
- 利点: token は DB 保管、`Token.objects.delete()` で即時失効可能
- 欠点: token は無期限 (TTL なし)。rotation を入れるには派生 ADR が必要
- 欠点: token 1 ユーザに 1 個 (デフォルト)。複数デバイス対応は Knox 等で拡張する派生余地

### 2. Django SessionAuthentication (cookie + CSRF)

- 利点: Django デフォルト、admin と統一される
- 欠点: SPA から `fetch` で叩くとき **CSRF token を都度取り回す**必要 (`/csrf` endpoint or meta tag)
- 欠点: cross-origin (Next.js dev server :3045 ↔ Django :3050) で cookie + CSRF 設定が複雑化
- 欠点: SSE / WebSocket と組み合わせるとき扱いが煩雑

### 3. JWT (`djangorestframework-simplejwt`)

- 利点: stateless、token に claim を埋め込める
- 利点: refresh token の rotation 機構が組み込み
- 欠点: 失効が厄介 (blacklist テーブルを別途持たないと revocation できない)
- 欠点: claim の意味設計 (exp / iat / iss) を学ぶ価値はあるが、`perplexity` で rodauth + JWT bearer 経路を学習済み (ADR 0007)。本プロジェクトでは別の手段を学ぶ方が学習効果が高い
- 欠点: localStorage に置いた JWT は SessionAuth と XSS リスク差が小さい (どちらも store 次第)

### 4. `django-allauth` (rodauth 相当の多機能)

- 利点: signup / verify / password reset / OAuth / 2FA を全部入りで提供
- 欠点: スコープ過剰 (CLAUDE.md「認証手段の網羅は除外」に正面から反する)
- 欠点: 学習対象が「1 経路の最小構成」から「allauth の設定網羅」に逸れる

### 5. 自前 token 実装

- 利点: 完全に学習対象を握れる
- 欠点: 車輪の再発明、車輪以下になりがち (timing attack / hash 衝突 / DB lookup)
- 欠点: DRF 標準で十分

## 採用理由

- **学習価値**: DRF の認証フレームワーク (`authentication_classes` / `permission_classes`) と Django の `User` model を最短経路で学べる。`rest_framework.authtoken` は **DRF 採用プロジェクトのデファクト一手目**として実務感も高い
- **アーキテクチャ妥当性**: 公開 API を持つ Django プロジェクトで最もよく見る構成
- **責務分離**: 認証は ViewSet 全体に `permission_classes = [IsAuthenticated]` で集約、business logic に漏れない
- **将来の拡張性**: TTL / rotation / 複数デバイス対応は派生 ADR で `Knox` への置き換えとして扱える
- **`perplexity` との対比**: rodauth-rails JWT bearer (Rails 生態系) ↔ DRF TokenAuthentication (Django 生態系) の **「同じ役割を異なる FW でどう実装するか」** が言語別バックエンド学習の主旨に合う

## 却下理由

- **SessionAuth**: SPA + cross-origin で CSRF / cookie の扱いが煩雑、学習対象が認証本筋から逸れる
- **JWT**: `perplexity` で同種を学習済み、本プロジェクトでは別手段で学ぶ方が学習効果が高い。失効管理の煩雑さも考慮
- **django-allauth**: スコープ過剰、CLAUDE.md の方針に反する
- **自前 token**: 車輪の再発明

## 引き受けるトレードオフ

- **token 無期限**: ログアウトしない限り永続。盗まれた場合の被害が大きい → 派生 ADR で TTL / rotation / Knox 移行を扱う余地。MVP では受容
- **複数デバイスで token が共有される**: `get_or_create(user=user)` で 1 ユーザ 1 token。ブラウザとモバイル並走には未対応 → 派生 ADR で Knox or simplejwt rotation
- **localStorage に token**: XSS で抜かれるリスク。CLAUDE.md の方針 (UI 作り込みを除外) と整合する範囲では許容、CSP / sanitize で副次的に防御
- **password reset 経路なし**: 1 経路スコープ外。実装するなら派生 ADR
- **email verification なし**: 1 経路スコープ外
- **DRF Browsable API は dev のみ**: production では無効化 (`DEFAULT_RENDERER_CLASSES` で `JSONRenderer` のみ)

## このADRを守るテスト / 実装ポインタ（Phase 2 以降で実装）

- `instagram/backend/config/settings.py` — `REST_FRAMEWORK = { 'DEFAULT_AUTHENTICATION_CLASSES': ['rest_framework.authentication.TokenAuthentication'], 'DEFAULT_PERMISSION_CLASSES': ['rest_framework.permissions.IsAuthenticated'] }`
- `instagram/backend/accounts/views.py` — `RegisterView` / `LoginView` / `LogoutView`
- `instagram/backend/accounts/serializers.py` — username / password validation
- `instagram/backend/accounts/tests/test_auth.py` — register → login → token で保護 endpoint 叩く / logout で無効化
- `instagram/backend/accounts/tests/test_unauthenticated.py` — 401 が全 endpoint で返る
- `instagram/frontend/src/lib/api.ts` — fetch に `Authorization: Token` を付与する wrapper

## 関連 ADR

- ADR 0001: timeline 読み出しは `request.user` で絞り込む (本 ADR が前提)
- ADR 0002: follow 操作は `request.user` で `follower` を確定する
- ADR 0011 (派生予定): token TTL / rotation (Knox 移行)
- ADR 0012 (派生予定): password reset / email verification
- 関連: `perplexity/docs/adr/0007-auth-rodauth-jwt-bearer.md` — Rails 側で同役割
