# Service Architecture Lab

有名 SaaS のアーキテクチャをローカル環境で再現し、設計理解と技術力向上を目指す検証用プロジェクト群。

> 単なるクローンではなく「サービスが解いている技術課題を、小さく再現する」ことを目的とする。  
> 設計方針は [CLAUDE.md](CLAUDE.md)、各プロジェクトの詳細はそれぞれの `README.md` を参照。

---

## プロジェクト一覧

| プロジェクト | サービス | 主な技術課題 | ステータス | ドキュメント |
| --- | --- | --- | --- | --- |
| [`slack`](slack/) | Slack 風リアルタイムチャット | WebSocket fan-out / 既読 cursor 整合性 / Rails ↔ Python 境界 | 🟢 MVP 完成 (E2E 6 件通過) | [README](slack/README.md) ・ [Architecture](slack/docs/architecture.md) ・ [ADR (5)](slack/docs/adr/) |
| [`youtube`](youtube/) | YouTube 風動画プラットフォーム | 非同期動画変換パイプライン / 状態機械 / Rails ↔ Python 境界 (タグ抽出 / サムネ / レコメンド) / FULLTEXT ngram 検索 / Solid Queue (Redis 不使用) | 🟢 MVP 完成 (RSpec 55 件 + Playwright 4 件通過) | [README](youtube/README.md) ・ [Architecture](youtube/docs/architecture.md) ・ [ADR (6)](youtube/docs/adr/) |
| [`github`](github/) | GitHub 風 Issue Tracker | 権限グラフ / Issue・PR モデル / CI ステータス集約 / GraphQL field 認可 | 🟢 MVP 完成 (RSpec 63 件 + Playwright 4 件通過) | [README](github/README.md) ・ [Architecture](github/docs/architecture.md) ・ [ADR (4)](github/docs/adr/) |

---

## 候補プロジェクト（検討中）

「着手するなら何が学びになるか」を整理しているストック。実際に着手する時点で ADR を書きスコープを確定させる。

### AI / LLM テーマ

LLM・AI エージェントを横断的に学ぶための案。

| 候補 | モチーフ | 主な技術課題 |
| --- | --- | --- |
| AI Coding Agent | Cursor / Devin / Cline | LLM tool use ループ / sandbox 隔離 / streaming / agent state machine ・中断/再開 |
| AI Workflow 自動化 | Zapier + AI / n8n | trigger→action DAG 実行 / connector プラグイン / 冪等性・リトライ |
| AI 検索 | Perplexity | RAG / マルチエージェント協調（検索→抽出→統合）/ 引用つき streaming |
| AI カスタマーサポート | Intercom Fin / Zendesk AI | KB の RAG 検索 / human-in-the-loop / エスカレーション state machine |

> LLM 本体はローカル完結方針に従い ai-worker でモック応答（tool call JSON 含む）を返す。

### 既存サービスをモチーフにしたテーマ

| 候補 | モチーフ | 主な技術課題 |
| --- | --- | --- |
| `discord` | Discord | 大規模ギルド fan-out / voice channel (WebRTC SFU) / 権限ビットマスク・ロール継承 |
| `figma` | Figma | リアルタイム共同編集 (CRDT) / multiplayer cursor / undo/redo の協調 |
| `stripe` | Stripe | idempotency key 設計 / webhook 配信保証（at-least-once + 順序）/ 決済 state machine / 通貨計算 |
| `shopify` | Shopify | **モジュラーモノリス (Rails Engine 分割)** / マルチテナント / 在庫整合性（同時減算）/ App プラットフォーム |
| `zoom` | Zoom | WebRTC SFU / 大規模 conference 参加者 / 録画パイプライン / 共有画面 |
| `chatgpt` | ChatGPT | LLM streaming / context window 管理 / tool calling / 会話履歴の永続化と分岐 |
| `uber` | Uber | **マイクロサービス** の代表題材 / 位置情報ストリーム / マッチングアルゴリズム / 配車 state machine / サービス間 saga・整合性 |
| `cursor` | Cursor | コード補完 streaming / repository context window 管理 / agent edit loop / 差分適用 sandbox |
| `perplexity` | Perplexity | RAG パイプライン (検索→抽出→LLM 合成) / 引用整合性 / 結果 streaming / Rails ↔ ai-worker の自然な責務分離 |
| `notebooklm` | NotebookLM | マルチドキュメント取り込み / 埋め込み・ベクタ検索 / ノート単位権限 / 引用付き回答 |

### 候補同士の組み合わせ・棲み分け

- **`shopify`** は本リポで唯一「モジュラーモノリス」を正面から扱う候補。Rails Engine 分割 / 内部境界 / 依存方向の規律が中心テーマ
- **`uber`** は対照的に「マイクロサービス」の正面題材。`shopify` と同時期に着手すれば**同規模ドメインで monolith vs microservices の対比**ができる
- **AI Coding Agent / `cursor` / `chatgpt`** はテーマが近接。`cursor` を選べば `chatgpt` の課題（streaming / context / tool）はおおむね包含する
- **AI 検索 / `perplexity` / `notebooklm`** はいずれも RAG が中核。`perplexity` は web 検索的な広域取得、`notebooklm` はユーザー所有ドキュメントへの限定取得という違い
- **`discord` / `zoom`** は voice / video の有無で違いを出す。Slack で扱った fan-out の規模感を超えたい場合は discord、WebRTC を中心に学びたい場合は zoom
- **AI Workflow** は microservices の練習に最適（trigger / executor / connector の自然な分割）

---

## slack プロジェクトのハイライト

- **2 BrowserContext での双方向 WebSocket fan-out** を Playwright で E2E 検証（[ADR 0001](slack/docs/adr/0001-realtime-delivery-method.md)）
- **既読 cursor の単調増加ガード** + 多デバイス同期の broadcast を minitest で検証（[ADR 0002](slack/docs/adr/0002-message-persistence-and-read-tracking.md)）
- **Slack 実構成と整合する MySQL** + Vitess 想定の言及（[ADR 0003](slack/docs/adr/0003-database-choice.md)）
- **rodauth-rails + JWT** によるクロスオリジン認証（[ADR 0004](slack/docs/adr/0004-authentication-strategy.md)）
- **Rails ↔ Python ai-worker** の責務境界（FastAPI モック要約）

技術スタック: Next.js 16 / React 19 / Tailwind v4 / Rails 8 (API) / rodauth-rails / ActionCable / Python 3.13 / FastAPI / MySQL 8 / Redis 7 / Playwright

---

## ディレクトリ構成

```text
service-architecture-lab/
  slack/                  # Slack 風 (実装済み / E2E 通過)
  youtube/                # YouTube 風 (MVP 完成 / E2E 通過)
  github/                 # GitHub 風 (MVP 完成 / E2E 通過)
  docs/                   # 共通ルール（走りながら整備）
  infra/
    terraform/            # 「本番化するなら」の設計図のみ（未実行）
  CLAUDE.md               # 設計方針・スコープ・ADR 運用
  Makefile                # 各サービスの起動 / テスト / lint のショートカット (`make help`)
  .github/workflows/      # CI (GitHub Actions)
```

---

## CI

GitHub Actions でプロジェクトごとに lint / test を並列実行する。

- **backend**: MySQL + Redis サービスを立ち上げて Rails minitest を実行
- **frontend**: ESLint + TypeScript の型チェック
- **ai-worker**: requirements を解決してインポート確認 + uvicorn boot smoke

設定は [`.github/workflows/ci.yml`](.github/workflows/ci.yml)。

---

## 起動 / テスト

トップレベルの `Makefile` に各サービスの起動・テスト・lint をショートカット化している。  
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

## ライセンス

学習・ポートフォリオ目的の個人プロジェクト。
