# ADR 0004: rodauth-rails JWT を REST + ActionCable 両方で（1 経路）

## ステータス

Accepted（2026-06-03）

## コンテキスト

figma は REST（ロード・作成・catch-up・ai-worker proxy）と ActionCable（op 投入・受信・cursor）の **2 つの経路**を持つ。両方で「誰が編集しているか（actor_id）」を確定する必要がある。actor_id は ADR 0001 の LWW tie-break と ADR 0002 の `operations.actor_id` に直結するため、**認証は収束ロジックの前提**。

制約・方針:

- 本リポは認証を **「最小 1 経路」** に絞る（policy のスコープ）。OAuth / SAML / 2FA は扱わない。
- 既存の Rails プロジェクト（perplexity / shopify / zoom / calendly）は **rodauth-rails の JWT bearer** を 4 連続で採用し、共通規律が `docs/api-style.md` に蓄積済み。
- `slack` は rodauth + JWT を **REST と ActionCable（WebSocket）両方**で使う先行例がある（同じ token を `Authorization: Bearer` と WS で共有）。
- frontend は Next.js。token を保持し REST header と ActionCable connection の両方に載せる。

## 決定

**rodauth-rails の JWT bearer を、REST と ActionCable の両経路で共有** する（slack 同方針、1 経路）。

- REST: `Authorization: Bearer <jwt>` を rodauth の JWT 機能で検証 → `current_account`。
- ActionCable: `Connection#connect` で **同じ JWT** を検証して `identified_by :current_user`（`reject_unauthorized_connection` で失敗時 reject）。token は接続確立時に渡す（slack の方式を踏襲）。
- `DocumentChannel#subscribed` で `document_members` を SELECT し、**member でなければ reject**（権限の第 1 段）。`apply_operation` 時に role を見て **viewer は op 拒否**（権限の第 2 段、ADR 0001 の「server 権威 = 権限検証」）。
- actor_id = `current_user.id`。op の `actor_id` / LWW tie-break / cursor の actor 表示に使う。

## 検討した選択肢

### 1. rodauth-rails JWT を REST + ActionCable 共有 ← 採用

- 既存 4 プロジェクトの規律をそのまま再利用（学習の重複を避け、figma 固有課題に集中できる）。
- 1 つの token で 2 経路をカバー。frontend の実装も単純。

### 2. セッション cookie（REST）+ WS は別トークン

- ブラウザ標準の cookie に乗れる。
- 欠点: 経路ごとに認証方式が分裂。Next.js（別オリジン）との CORS / cookie 共有が面倒。1 経路方針に反する。

### 3. OAuth / Devise などフル機能認証

- 本物に近い。
- 欠点: policy のスコープ外（認証網羅は学びが薄い）。figma の技術課題（収束）に無関係。

## 採用理由

- **学習価値**: figma 固有の学び（LWW 収束 / op log / Solid Cable）に集中するため、認証は**確立済みパターンの再利用**が最適。新規性を求める領域ではない。
- **アーキテクチャ妥当性**: 同一 JWT を REST + WS で共有するのは実プロダクトでも一般的。
- **責務分離**: 認証（誰か）と認可（document member / role）を分け、認可は channel / controller の前置きで効かせる。
- **将来の拡張性**: チーム / 組織階層の権限グラフに発展する余地（github の PermissionResolver 的 2 層）を残す。

## 却下理由

- 案 2（cookie + 別トークン）: 経路分裂 + CORS 複雑化、1 経路方針に反する。
- 案 3（OAuth フル）: スコープ外、技術課題に無関係。

## 引き受けるトレードオフ

- **JWT revocation**: bearer JWT は失効が難しい（短命 token + refresh で緩和、既存規律踏襲）。MVP では許容。
- **WS の token 受け渡し**: 接続確立時の token 受け渡し方式（query / header / sub-protocol）はブラウザ WS API の制約を受ける。slack の先行実装に合わせる。
- **権限の 2 段構え**: subscribe 時の member 判定と apply 時の role 判定で 2 回権限を見る（DRY ではないが、購読と書き込みで意味が違うので明示的に分ける）。

## このADRを守るテスト / 実装ポインタ

- `figma/backend/spec/channels/document_channel_spec.rb`（予定）— 未認証 connection は reject / 非 member は subscribe 拒否 / viewer の `apply_operation` は拒否。
- `figma/backend/app/channels/application_cable/connection.rb`（予定）— JWT 検証 + `identified_by`。
- `docs/api-style.md` — rodauth-rails JWT bearer の共通規律（perplexity / shopify / zoom / calendly で確立、figma が 5 例目）。

## 関連 ADR

- ADR 0001: actor_id が LWW tie-break に使われる
- ADR 0002: `operations.actor_id` の出所
- ADR 0003: ActionCable connection の identification
