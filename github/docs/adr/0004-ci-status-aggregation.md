# ADR 0004: CI ステータスの集約方式

## ステータス

Accepted（2026-05-01）

## コンテキスト

PR には複数の CI チェック (`build`, `test`, `lint`, ...) が並列で動き、それぞれが `pending → success / failure` と遷移する。
PR 上では **「全チェックが success なら緑、1 つでも failure なら赤、それ以外は黄」** という集約結果を表示したい。

制約：

- ローカル完結（外部 CI は呼ばない）。本物の CI ランナーではなく、**ai-worker からモックの check 状態をポストする** 形を想定
- 実 GitHub Actions / external check の API 互換は不要。**集約ロジックの設計だけを学ぶ**
- 同じチェック名で複数回 push されたら **head SHA + check_name に対して最新が勝つ**
- GraphQL で `pullRequest.checkStatus` を 1 回のクエリで取得できること（ADR 0001）

## 決定

**「`commit_checks` テーブルで個別チェックを永続化し、PR の `head_sha` に紐づく最新行を集約する」** を採用する。

- `commit_checks(id, repository_id, head_sha, name, state, started_at, completed_at, output)` — `state` は `pending | success | failure | error`
- 同一 `(repository_id, head_sha, name)` は **upsert**（最新が前を上書き）
- PR の集約状態は `PullRequest#aggregated_check_state` メソッドで動的計算：
  - 全 success → `success`
  - 1 つでも failure / error → `failure`
  - pending が混ざっていれば → `pending`
- ai-worker → backend の通知は **REST POST `/internal/commit_checks`**（GraphQL は外向け、内部 trusted ingress は REST が素直）
- 集約状態の **realtime 反映は subscription ではなく polling**（5s）。subscription は Phase 5 以降の延長課題に置く

## 検討した選択肢

### 1. `commit_checks` upsert + 動的集約 ← 採用

- 履歴 (started_at / completed_at) も保持できる
- PR ごとの集約は `head_sha` をキーに JOIN するだけ
- 利点: 集約ロジックが Ruby のメソッド 1 つで読める

### 2. PR テーブルに `check_status` カラムを直接持つ

- クエリは最速
- 欠点: **どのチェックが落ちたか**が見えない。学習対象から逸れる

### 3. checks の状態遷移を AASM / state_machines gem で管理

- 状態遷移は厳密になる
- 欠点: gem の使い方を学ぶ比重が増え、集約という本題から逸れる

### 4. GraphQL Subscription でリアルタイム配信

- UI 体験は最も近い
- 欠点: ActionCable の AnyCable / GraphQL subscription は学習スタックが膨らむ
- 欠点: Phase 1〜4 のスコープ外。後続 ADR で扱う余地あり

## 採用理由

- **学習価値**: 「集約は派生値、永続化は個別チェック単位」という分割を明示的に書ける
- **アーキテクチャ妥当性**: 実 GitHub の Checks API も個別チェック + 集約 view という構造
- **責務分離**: ai-worker は単に check を投げる側、集約は backend、表示は frontend と層が分かれる
- **将来の拡張性**: subscription 化 / external check provider 抽象化など段階的に伸ばせる

## 却下理由

- PR テーブル直書き: どのチェックが落ちたかが追えない
- AASM: 学習対象が逸れる
- GraphQL subscription: スコープ外（延長課題に明記）

## 引き受けるトレードオフ

- **PR ごとに JOIN が走る**: PR 一覧で N+1 を起こしやすい。`graphql-batch` で `head_sha` まとめて取得するのが必須 (ADR 0001 と整合)
- **realtime 性**: polling 5s で UX は十分だが、実 GitHub のような instant 更新ではない
- **history**: 同じ check 名の履歴は upsert で潰す。再 push 前の結果を残したいユースケースは扱わない
- **失敗の細分化**: `failure` と `error` の 2 値を持つが、UI 上は同じ「赤」。学習用途では分ける意味が薄いが、ai-worker が分けて投げる練習として残す

## このADRを守るテスト / 実装ポインタ（Phase 2 以降）

- `github/backend/db/migrate/*_create_commit_checks.rb`
- `github/backend/app/models/commit_check.rb` — upsert ヘルパー
- `github/backend/app/models/pull_request.rb` — `aggregated_check_state`
- `github/backend/app/controllers/internal/commit_checks_controller.rb` — ai-worker からの ingress
- `github/backend/spec/models/pull_request_check_aggregation_spec.rb`

## 関連 ADR

- ADR 0001: GraphQL 採用 (集約は GraphQL field で expose)
- ADR 0003: PR データモデル (`head_sha` を保持する場所)
