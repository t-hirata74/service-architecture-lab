# Service Architecture Lab

有名 SaaS のアーキテクチャを参考に、**ローカル完結**のミニマム構成で検証するプロジェクト群。設計理解・技術力向上・ポートフォリオが目的。

**詳細方針（完成定義・ADR・スコープ・各プロジェクトの機能一覧・Rails リプレイス）:** [`docs/service-architecture-lab-policy.md`](docs/service-architecture-lab-policy.md)

---

## 目的（要約）

- アーキテクチャ理解、Next.js / Rails / Python の実践、Rails 実務構成の検証
- AI・データ処理を含む設計、GitHub 上での提示

---

## 必須方針

### 外部 API は使わない

- ローカル完結、モック・ダミーデータ、外部依存を置かない

### リポジトリ構成（目安）

```txt
service-architecture-lab/
  <service>/
    frontend/     # 必要なプロジェクトのみ
    backend/      # Rails または他言語
    ai-worker/    # Python（モック可）
    docs/         # ADR・プロジェクト固有ドキュメント
    docker-compose.yml
    README.md
    infra/terraform/   # 設計図（terraform apply はしない想定）
  docs/           # 共通ルール（本リポの索引は policy 参照）
```

---

## スタックの役割

| 層 | 担当 |
| --- | --- |
| **Frontend（React/Next.js）** | UI、App Router、SSR/CSR/ISR、認証セッションと API、WebSocket/SSE 購読層、必要なら Zustand / TanStack Query、BFF 的接続 |
| **Backend（Rails 等）** | 認証、CRUD、DB、権限、GraphQL/REST、ドメインロジック |
| **Python（ai-worker）** | AI（モック可）、レコメンド、検索ランキング、テキスト処理、バッチ、非同期ワーカー |

---

## 完成の定義（要約）

ローカル起動、主要ユースケースの動作確認、技術課題がコードから読み取れること、`<service>/README` にアーキ図と手順、root `README` の一覧表更新、**ADR 最低3本**、CI に lint/test。**網羅ではなく「学びと動作確認ができる」基準。** 全文は policy 参照。

**ADR:** `<service>/docs/adr/`、書式・運用は [`docs/adr-template.md`](docs/adr-template.md) と policy。

---

## スコープ（要約）

「そのサービスの技術課題の理解が深まるか」で含む/捨てる。含める例：WebSocket fan-out、ワーカーと状態機械、DB・権限、Rails↔ai-worker 境界、認証1経路。捨てる例：課金フル、認証の網羅、リッチ UI の作り込み等。**判断表・除外リストは policy。**

---

## 候補プロジェクト（検討中）

候補一覧は [README 候補プロジェクト節](README.md#候補プロジェクト検討中) を正とし、本書では要約のみ載せる。完成済みは [README プロジェクト一覧](README.md#プロジェクト一覧)。両方を編集する場合は同期する。

| 候補 | Backend 想定 | 主な技術課題（一言） |
| --- | --- | --- |
| `uber` | Go | 地理空間索引 / goroutine + channel / 配車 state machine |
| `figma` | 未定 | リアルタイム共同編集 (CRDT) / multiplayer cursor |
| `stripe` | 未定 | idempotency / at-least-once webhook / 決済 state machine |
| ~~`zoom`~~ → 着手 | Rails | 会議ライフサイクル state machine / ホスト権限 / 録画→要約パイプライン (Phase 1) |
| `chatgpt` | 未定 | LLM streaming / context window 管理 / tool calling |
| `cursor` | 未定 | コード補完 streaming / repository context / agent edit loop |
| `notebooklm` | 未定 | マルチドキュメント RAG / 埋め込み / ノート単位権限 |
| AI Coding Agent | 未定 | LLM tool use ループ / sandbox 隔離 / agent state machine |
| AI Workflow 自動化 | 未定 | trigger→action DAG / connector プラグイン / 冪等性 |
| AI カスタマーサポート | 未定 | KB の RAG 検索 / human-in-the-loop / エスカレーション |

機能詳細・ai-worker 役割・棲み分けは [README 候補プロジェクト節](README.md#候補プロジェクト検討中) と policy。LLM 本体は方針どおり **ローカル完結・モック可**（実 SDK 不使用）。

---

## 共通ドキュメント（`docs/`）

コーディング規約・Git・テスト等：[`docs/coding-rules/`](docs/coding-rules/)、[`docs/git-workflow.md`](docs/git-workflow.md)、[`docs/testing-strategy.md`](docs/testing-strategy.md)、[`docs/api-style.md`](docs/api-style.md)

---

## Claude Code 利用ガイド（学習プロジェクトとしての方針）

このリポジトリは「設計判断を自分で考えて学ぶ」ことが目的のため、Claude には以下の振る舞いを期待する。

### 1. 設計判断は「決め打ち」せず選択肢を提示

非自明な設計判断（DB 設計、状態機械、認証経路、ストリーミング方式、依存方向、テスト戦略 等）に直面したら、**実装に進む前に選択肢を 2〜3 個提示し、トレードオフを 1 行ずつ書く**。auto モードでも、設計判断はユーザー確認を挟む。typo 修正・lint 違反・テスト追加など機械的な作業は止めなくてよい。

### 2. 外部依存を勝手に増やさない

- 外部 SaaS / LLM API / マネージド検索 / マネージドキュー の SDK・クライアントは導入禁止（policy 準拠）
- 新規 gem / npm パッケージ / Python ライブラリの追加は、**導入前にユーザーに用途と代替案を確認**
- 既に入っている依存の利用は確認不要

### 3. ADR を書くタイミング

以下に該当する変更を行う場合、コードと一緒に `<service>/docs/adr/NNNN-*.md` を `docs/adr-template.md` の書式で起こす（テンプレ機械適用は `add-service` skill 参照）。

- レイヤー間の依存方向を変える / 新しい責務境界を引く
- 同時実行制御（楽観/悲観/条件付き UPDATE 等）を選ぶ
- ストリーミング/非同期方式（WS / SSE / polling / queue）を選ぶ
- マルチテナンシ・権限モデルの方針を決める
- フレームワーク内の構造（Rails Engine 分割、Django app 分割、FastAPI ルータ分割 等）を決める

逆に「実装方針の小さな選択（メソッド名、ファイル分割粒度）」では ADR を書かない。

### 4. サービスをまたぐ変更は事前に分割提案

`shopify/` を直すついでに `slack/` も触る、のような横断変更は、**まず「どのサービスをどの順で変えるか」をユーザーに確認**してから着手する。共通 `docs/` の更新は単独 PR で扱う。

### 5. 完成定義に従う

各サービスは「網羅」ではなく「学びと動作確認ができる」が基準（policy 完成定義）。Claude は機能を増やす方向に流れがちなので、**追加機能の提案は "技術課題の理解が深まるか" で判定**し、深まらないなら提案ごと却下する。

### 6. Phase 順は推奨順で進める（順序は確認しない）

Phase 区切り（Phase 4-1 / 4-2 / Phase 5 のサブステップ等）の順序判断に直面したら、**選択肢を並べてユーザに確認を取らず、Claude が推奨する順を採用して即着手**する。提案理由を 1 行添える程度で OK。ユーザは進行中に方針変更を伝えれば良い。**ルール1 (設計選択肢の提示) とは対象が異なる**: ルール1 は「何を作るか」の意思決定、本ルールは「順序」だけの軽量な判断であり、確認コストが学びを上回る。

ただし以下は例外で、引き続きユーザ確認を取る:

- 順序の前に **新しい Phase の存在自体** を提案するとき (例: 「Phase 6 として X を追加すべきか」)
- 既に走った Phase の結果を **覆す** 順序変更 (例: Phase 4 の認証実装を破棄して別方式に切り替える)

### 7. プロジェクトメモリの索引

このリポ専用のメモリは `~/.claude/projects/-Users-hiratatomoaki-work-service-architecture-lab/memory/` に保存される。プロジェクト固有の決定・ユーザー嗜好はそこに記録する。
