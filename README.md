# Service Architecture Lab

有名 SaaS のアーキテクチャを **ローカル完結のミニマム実装** で再現し、設計理解と技術力を実装で示す検証用プロジェクト群。

> 単なるクローンではなく **「サービスが解いている技術課題を、小さく動く形で再現する」** ことを目的とする。
> 機能網羅は除外（[スコープ判定基準](docs/service-architecture-lab-policy.md#scope)）、外部 SaaS 依存は禁止 (LLM や決済 / 動画コーデックも全部モック)。
> 設計判断はすべて **ADR (Architecture Decision Record)** で残し、後から「なぜそう作ったか」が読み取れる状態を保つ。

---

## プロジェクト一覧

| プロジェクト | サービス | 主な技術課題 | ステータス | ドキュメント |
| --- | --- | --- | --- | --- |
| [`slack`](slack/) | Slack 風リアルタイムチャット | WebSocket fan-out / 既読 cursor 整合性 / Rails ↔ Python 境界 | 🟢 MVP 完成 (E2E 6 件通過) | [README](slack/README.md) ・ [Architecture](slack/docs/architecture.md) ・ [ADR (6)](slack/docs/adr/) |
| [`youtube`](youtube/) | YouTube 風動画プラットフォーム | 非同期動画変換パイプライン / 状態機械 / Rails ↔ Python 境界 (タグ抽出 / サムネ / レコメンド) / FULLTEXT ngram 検索 / Solid Queue (Redis 不使用) | 🟢 MVP 完成 (RSpec 55 件 + Playwright 4 件通過) | [README](youtube/README.md) ・ [Architecture](youtube/docs/architecture.md) ・ [ADR (6)](youtube/docs/adr/) |
| [`github`](github/) | GitHub 風 Issue Tracker | 権限グラフ / Issue・PR モデル / CI ステータス集約 / GraphQL field 認可 | 🟢 MVP 完成 (RSpec 75 件 + Playwright 4 件通過) | [README](github/README.md) ・ [Architecture](github/docs/architecture.md) ・ [ADR (4)](github/docs/adr/) |
| [`perplexity`](perplexity/) | Perplexity 風 RAG 検索 | RAG パイプライン (retrieve / extract / synthesize) / Hybrid retrieval + embedding データ管理 / SSE streaming + 三段階 degradation / 引用整合性の信頼境界 / テスト戦略 / chunk 分割戦略 / rodauth-rails JWT bearer | 🟢 Phase 5 完了 (RSpec 105 + pytest 70 件 / Playwright scaffold / Terraform validate pass / CI 4 ジョブ追加) | [README](perplexity/README.md) ・ [Architecture](perplexity/docs/architecture.md) ・ [ADR (7)](perplexity/docs/adr/) |
| [`instagram`](instagram/) | Instagram 風タイムライン (Django/DRF) | タイムライン生成戦略 (fan-out on write) / フォローグラフ DB 設計 / Django ORM N+1 + index / DRF TokenAuthentication | 🟢 MVP 完成 (Django pytest 51 + ai-worker pytest 12 + Playwright 実機 3 件通過 / Terraform validate / CI 4 ジョブ) | [README](instagram/README.md) ・ [Architecture](instagram/docs/architecture.md) ・ [ADR (4)](instagram/docs/adr/) |
| [`discord`](discord/) | Discord 風リアルタイムチャット (Go) | ギルド単位シャーディング + 単一プロセス Hub / goroutine + channel CSP pattern / プレゼンスハートビート / WebSocket fan-out (slack Rails ActionCable との対比) | 🟢 MVP 完成 (Go gateway + WS Hub + Next.js 16 + ai-worker + Playwright fan-out / presence offline 2 ケース通過 / Terraform validate / CI 5 ジョブ) | [README](discord/README.md) ・ [Architecture](discord/docs/architecture.md) ・ [ADR (4)](discord/docs/adr/) |
| [`reddit`](reddit/) | Reddit 風 forum (FastAPI / async) | コメントツリー (Adjacency List + Materialized Path) / 投票整合性 (votes truth + posts.score 相対加算) / Hot ランキング (Reddit 公式式 + ai-worker APScheduler 60s 再計算) / FastAPI async + SQLAlchemy 2.0 async + aiomysql + HS256 JWT | 🟡 設計フェーズ完了 (ADR 4 本 + architecture.md + docker-compose) | [README](reddit/README.md) ・ [Architecture](reddit/docs/architecture.md) ・ [ADR (4)](reddit/docs/adr/) |

各プロジェクトは **backend (Rails 8) + frontend (Next.js 16) + ai-worker (Python / FastAPI) + MySQL** という同形構成。違いは **API スタイル / キュー / 認可モデル / 検索エンジン / streaming プロトコル** といった技術課題ごとの選択にある。

---

## プロジェクト横断のハイライト

「3 プロジェクト並べたから見える」設計の対比と、共通ドキュメントに昇華した知見。

### REST + OpenAPI ↔ GraphQL の選定対比

`docs/api-style.md` で **「主要技術課題に応じて API スタイルを選ぶ」** という方針を立て、3 プロジェクトで実際に使い分けた:

| プロジェクト | 採用 | 理由（要約） |
| --- | --- | --- |
| `slack` | REST + OpenAPI | 主要課題が WebSocket fan-out / 既読 cursor で API 形は固定形で十分 |
| `youtube` | REST + OpenAPI | 状態機械 + アップロードの action API が中心、リレーショナルな深掘りは弱い |
| `github` | **GraphQL** (graphql-ruby + urql) | Issue / PR / Review / Permission の関係グラフが主役、REST だと endpoint 爆発 |
| `perplexity` | REST + **SSE** (`ActionController::Live`) | 同期 API は固定形で十分、stream 部分のみ SSE で切り出す。slack の WebSocket / github の polling との対比が学習対象 |

GraphQL 採用時の **N+1 / Dataloader / field 認可** は `github` で実装し、`spec/graphql/n_plus_one_spec.rb` で SQL 件数を計測する形で固定。

### キュー / 状態機械の対比

| プロジェクト | キュー基盤 | 学んだこと |
| --- | --- | --- |
| `slack` | (リアルタイム配信のみ / Redis Pub/Sub) | ActionCable + Redis で fan-out。永続キューは扱わない |
| `youtube` | **Solid Queue (Redis 不使用)** | Rails 8 標準の DB-driven キュー。状態遷移と enqueue を **同一 MySQL トランザクション**に乗せる |
| `github` | (Solid Queue を入れたが未使用) | 内部 ingress (REST + 共有トークン) を ai-worker → backend で確立 |

### 認可モデルの対比

| プロジェクト | 認可の主役 | 場所 |
| --- | --- | --- |
| `slack` | リソース所有者ベース (channel membership) | controller の前置きで filter |
| `youtube` | 動画の visibility / 公開者ベース | controller filter + scope |
| `github` | **権限グラフ** (Org/Team/Collaborator の継承) | `PermissionResolver` (PORO) + `Pundit` policy の 2 層構造 |

### 共通ドキュメントに昇華した知見

6 プロジェクト (slack / youtube / github / perplexity / instagram / discord) で踏んだ落とし穴 / 確立したパターンを `docs/` 配下に整理。次のプロジェクトで同じ罠を踏まないための土台。

- **[docs/api-style.md](docs/api-style.md)** — REST/GraphQL 選定軸 + GraphQL 運用ルール (urql / graphql-codegen / Dataloader / Pundit 経由認可 / GET と POST 両受け / schema-dump CI guard)
- **[docs/framework-django-vs-rails.md](docs/framework-django-vs-rails.md)** — instagram で得た Django/DRF と Rails の比較 (Admin / `select_related` 明示 / `F()` 原子更新 / `assertNumQueries` 不変条件試験 / Apps 縦割り) + 選定判断軸
- **[docs/coding-rules/rails.md](docs/coding-rules/rails.md)** — Rails 8 enum の pluck が文字列を返す件 / `with_lock` 連番採番 / 認可 2 層 / TEXT に default を持たせない
- **[docs/coding-rules/python.md](docs/coding-rules/python.md)** — (A) ai-worker (FastAPI) + (B) Django/DRF backend のコーディング規約 (prefetch 必須化 / `F()` / signal + on_commit / management commands / Django Admin / Celery + settings の罠)
- **[docs/coding-rules/go.md](docs/coding-rules/go.md)** — Go を選ぶ判断軸 (long-lived 同接 / CSP 並行 / in-memory 状態機械) + discord で確立した規約 (chi / database/sql 生 SQL / log/slog / single-goroutine ownership / non-blocking send + drop / context 統一 / `go test -race` 必須) + Rails/Django 対比表
- **[docs/coding-rules/frontend.md](docs/coding-rules/frontend.md)** — urql Provider は `useState(() => createClient())` で 1 度だけ生成 / 401 自動 redirect / `useSyncExternalStore` で localStorage 同期 + 同一タブ synthetic `storage` event
- **[docs/operating-patterns.md](docs/operating-patterns.md)** — 内部 trusted ingress (REST + 共有トークン) / SSE 三段階 degradation / **fan-out on write** + soft delete + delete propagation / **denormalized counter + recount management command** / Django ↔ FastAPI 内部 token / **single-process Hub goroutine + CSP fan-out (discord)**
- **[docs/testing-strategy.md](docs/testing-strategy.md)** — N+1 spec / field-level auth spec / Pundit Scope spec / **N+1 不変条件試験 (Django)** / `transaction.on_commit` 同期化 / Celery EAGER + sqlite StaticPool / **Hub の concurrency 不変条件 + `go test -race` 必須 (Go)**

---

## 技術スタック (横並び)

| | slack | youtube | github | perplexity |
| --- | --- | --- | --- | --- |
| Frontend | Next.js 16 / React 19 / Tailwind v4 | 同左 | 同左 + **urql** + graphql-codegen | 同左 + **fetch ReadableStream** で SSE 受信 |
| Backend | Rails 8 (API) / rodauth-rails / ActionCable | Rails 8 (API) / **Solid Queue** / Active Storage | Rails 8 (API) / **graphql-ruby** / Pundit / Solid Queue | Rails 8 (API) / **`ActionController::Live`** で SSE proxy |
| ai-worker | FastAPI / Python 3.13 (要約 mock) | FastAPI (recommend / tags / thumbnail) | FastAPI (review / code-summary / check/run) | FastAPI (retrieve / extract / synthesize-stream) + **numpy** |
| 永続化 | MySQL 8 + **Redis 7** | MySQL 8 のみ (Solid Queue/Cache 同居) | MySQL 8 のみ | MySQL 8 のみ (chunk.embedding を BLOB で保持) |
| API | **REST + OpenAPI** | REST + OpenAPI | **GraphQL** | REST + **SSE** (stream 部分のみ) |
| 認可 | controller filter | controller + scope | **Pundit + PermissionResolver の 2 層** | controller filter (query.user_id == current_user) |
| キュー | (なし) | **Solid Queue** (DB-driven) | (Solid Queue 同梱だが未使用) | (なし / SSE は同期接続) |
| 検索 | (なし) | **MySQL FULLTEXT (ngram)** | (なし) | **Hybrid (FULLTEXT ngram + 擬似ベクタ cosine)** |
| streaming | **WebSocket** (ActionCable + Redis) | (なし / polling) | (なし / polling) | **SSE** (ActionController::Live + fetch ReadableStream) |
| E2E | Playwright (chromium) 6 件 | Playwright 4 件 | Playwright 4 件 | (Phase 5 で追加予定) |
| CI | github-actions | 同左 | 同左 (4 ジョブ × 3 プロジェクト = 12 ジョブ並列) | (Phase 5 で追加予定) |

---

## 言語別バックエンド方針

本リポジトリのオーナーは **Rails エンジニア** を主軸としつつ、**Python (Django/FastAPI) と Go のナレッジ**も並走で獲得する方針を取る。よって候補プロジェクトはバックエンド言語を「その言語が選ばれる典型ドメイン」に紐付けて選定する。

| バックエンド | プロジェクト | 主な学習対象 |
| --- | --- | --- |
| **Rails** | slack / youtube / github / perplexity | WebSocket fan-out / 状態機械 / 権限グラフ / SSE + RAG |
| **Python (Django/DRF)** | instagram (Phase 1 設計完了) | Django ORM / タイムライン生成 (push vs pull) / フォローグラフ |
| **Python (FastAPI)** | reddit (Phase 1 設計完了) | 非同期 I/O / コメントツリー DB 設計 / Hot ランキング |
| **Go** | uber (候補) | goroutine / 地理空間インデックス (S2/Geohash/H3) / 配車 state machine |
| **Go** | discord (MVP 完成) | WebSocket fan-out / ギルド単位シャーディング / プレゼンス整合性 |

### Rails リプレイス学習

Python / Go で実装したプロジェクト完成後に、**Rails で再実装する別プロジェクト**を作ることを学習オプションとして許容する (例: `instagram/` → `instagram-rails/`)。

```text
service-architecture-lab/
  instagram/          # Django/DRF 版 (オリジナル)
  instagram-rails/    # Rails 再実装版 (学習用リプレイス)
```

目的:

- 同じドメインを **言語/FW を変えて実装し直す**ことで、各 FW の思想・ORM・非同期モデルの違いを体感する
- Rails への置き換え時に「Django/FastAPI/Go の何が代替しづらいか」を ADR に残す (例: Django Admin、FastAPI の型駆動、Go の並行性 など)
- リプレイス版は **オリジナル版の完成後**に着手し、同時並行はしない
- リプレイス版でも ADR 最低 3 本・README・CI 追加など「完成の定義」は同じ基準を満たす

---

## 候補プロジェクト（検討中）

「着手するなら何が学びになるか」を整理しているストック。実際に着手する時点で ADR を書きスコープを確定させる。

### 言語別ナレッジ獲得テーマ

上記「言語別バックエンド方針」に沿って、Python / Go の実務感覚を獲得するためのプロジェクト群。

| 候補 | バックエンド | モチーフ | 主な技術課題 |
| --- | --- | --- | --- |
| ~~`reddit`~~ → 着手 | **Python (FastAPI)** | Reddit | コメントツリー DB 設計 / 投票スコア整合性 / Hot ランキング (本リポに着手済み、Phase 1 完了) |
| `uber` | **Go** | Uber | 地理空間インデックス (S2/Geohash/H3) / goroutine + channel での並行マッチング / 配車 state machine |

### AI / LLM テーマ

LLM・AI エージェントを横断的に学ぶための案。

| 候補 | モチーフ | 主な技術課題 |
| --- | --- | --- |
| AI Coding Agent | Cursor / Devin / Cline | LLM tool use ループ / sandbox 隔離 / streaming / agent state machine ・中断/再開 |
| AI Workflow 自動化 | Zapier + AI / n8n | trigger→action DAG 実行 / connector プラグイン / 冪等性・リトライ |
| AI カスタマーサポート | Intercom Fin / Zendesk AI | KB の RAG 検索 / human-in-the-loop / エスカレーション state machine |

> LLM 本体はローカル完結方針に従い ai-worker でモック応答（tool call JSON 含む）を返す。

### その他の既存サービスモチーフ

| 候補 | モチーフ | 主な技術課題 |
| --- | --- | --- |
| `figma` | Figma | リアルタイム共同編集 (CRDT) / multiplayer cursor / undo/redo の協調 |
| `stripe` | Stripe | idempotency key 設計 / webhook 配信保証（at-least-once + 順序）/ 決済 state machine / 通貨計算 |
| `shopify` | Shopify | **モジュラーモノリス (Rails Engine 分割)** / マルチテナント / 在庫整合性（同時減算）/ App プラットフォーム |
| `zoom` | Zoom | WebRTC SFU / 大規模 conference 参加者 / 録画パイプライン / 共有画面 |
| `chatgpt` | ChatGPT | LLM streaming / context window 管理 / tool calling / 会話履歴の永続化と分岐 |
| `cursor` | Cursor | コード補完 streaming / repository context window 管理 / agent edit loop / 差分適用 sandbox |
| `notebooklm` | NotebookLM | マルチドキュメント取り込み / 埋め込み・ベクタ検索 / ノート単位権限 / 引用付き回答 |

### 候補同士の組み合わせ・棲み分け

- **`uber` (Go)** と **`discord` (Go)** はどちらも「Go の高並行性」を扱うが、`uber` は **地理空間 + 状態機械**、`discord` は **fan-out + シャーディング**に焦点を寄せる。`discord` は既存の `slack` (Rails) と用途が近接するので、**Slack との実装比較**を学習素材にする位置づけ
- **`instagram` (Django)** と **`reddit` (FastAPI)** は同じ Python でも **同期 ORM + 管理画面前提** と **非同期 I/O + 型駆動** で対照的。両方やると Python Web フレームワーク二大潮流を比較できる
- **`shopify`** は本リポで唯一「モジュラーモノリス」を正面から扱う候補。Rails Engine 分割 / 内部境界 / 依存方向の規律が中心テーマ。`uber` (マイクロサービス的分散) と同時期に着手すれば **monolith vs microservices の対比**ができる
- **AI Coding Agent / `cursor` / `chatgpt`** はテーマが近接。`cursor` を選べば `chatgpt` の課題（streaming / context / tool）はおおむね包含する
- **`notebooklm`** は本リポの `perplexity` (広域取得 / 引用 streaming) と対比して **ユーザー所有ドキュメントへの限定取得 + ノート単位権限** が中心テーマ。同じ RAG でも入力側 (web 検索 vs ユーザコーパス) と権限モデルで差別化
- **`zoom`** は voice / video を中心に学びたい場合の候補。`discord` で扱う fan-out との差は WebRTC の有無
- **AI Workflow** は microservices の練習に最適（trigger / executor / connector の自然な分割）

---

## ディレクトリ構成

```text
service-architecture-lab/
  slack/                  # Slack 風 (MVP / E2E 通過)
  youtube/                # YouTube 風 (MVP / E2E 通過)
  github/                 # GitHub 風 (MVP / E2E 通過)
  perplexity/             # Perplexity 風 (Phase 5 完了 / RAG + SSE)
  instagram/              # Instagram 風 (Django/DRF / MVP 完成 / fan-out + Celery)
  discord/                # Discord 風 (Go / MVP 完成)
  reddit/                 # Reddit 風 (FastAPI / 設計フェーズ完了)
  docs/                   # 共通ルール (走りながら整備)
    api-style.md          # REST/GraphQL 選定 + GraphQL 運用
    coding-rules/         # rails / frontend / python / go の規約
    operating-patterns.md # 内部 ingress / cache busting / graceful degradation
    testing-strategy.md   # 各プロジェクトのテスト方針
    git-workflow.md       # ブランチ / コミット規約
    adr-template.md       # ADR の雛形
    service-architecture-lab-policy.md  # 完成定義・ADR 運用・スコープ・プロジェクト一覧（詳細）
  CLAUDE.md               # エージェント向け要約（詳細は docs/service-architecture-lab-policy.md）
  Makefile                # 各サービスの起動 / テスト / lint のショートカット (`make help`)
  .github/workflows/      # CI (GitHub Actions)
```

---

## CI

GitHub Actions で **3 プロジェクト × 4 ジョブ (= 12 ジョブ)** を並列実行。

- **backend**: MySQL (+ slack のみ Redis) サービス起動 → `db:create db:migrate` → minitest / RSpec
- **frontend**: ESLint + TypeScript + (Next.js) build
- **ai-worker**: pip install + import smoke + uvicorn boot smoke (wait-loop で flake 防止)
- **terraform**: fmt + init + validate (本番想定設計図の構文チェック)

加えて **openapi-lint** ジョブで slack / youtube の OpenAPI を Redocly CLI で lint、**github-backend** では GraphQL schema dump を CI で diff チェック (生成スキーマと commit スキーマが一致するかを保証)。

設定は [`.github/workflows/ci.yml`](.github/workflows/ci.yml)。

---

## 起動 / テスト

トップレベルの `Makefile` に各サービスの起動・テスト・lint をショートカット化。
全ターゲットは `make help` で確認できる。

```bash
make help                       # ターゲット一覧 (サービス別にグルーピング)

# 例: slack を一通り起動
make slack-deps-up              # mysql:3307 / redis:6379
make slack-backend              # Rails API :3010
make slack-ai                   # FastAPI :8000        (別タブ)
make slack-frontend             # Next.js :3005        (別タブ)
make slack-e2e                  # Playwright E2E       (起動後に実行)

# CI 相当のチェックをローカルで一括実行
make ci-local                   # openapi-lint + 各サービスの test + lint
```

サービス固有の詳細手順は各 README を参照: [slack](slack/README.md) ・ [youtube](youtube/README.md) ・ [github](github/README.md)

---

## 各プロジェクトのハイライト (1 行紹介)

- **[slack](slack/README.md)** — 2 BrowserContext で **WebSocket fan-out** を E2E 検証 / 既読 cursor の単調増加ガード / rodauth-rails + JWT で REST と WebSocket 両方を同じ token で
- **[youtube](youtube/README.md)** — `uploaded → transcoding → ready → published` の状態機械を **Solid Queue + 同一 MySQL トランザクション**で原子的に駆動 / **MySQL FULLTEXT (ngram) で日本語検索**を MVP
- **[github](github/README.md)** — **権限グラフ**を `PermissionResolver` 1 箇所に集約 + Pundit verb で適用 / **graphql-ruby Dataloader で N+1 を SQL 本数固定** / Issue と PR の **番号空間共有**を `with_lock` で実装 / ai-worker → 内部 REST ingress → GraphQL バッジ反映を Playwright で E2E

---

## ライセンス

学習・ポートフォリオ目的の個人プロジェクト。
