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

## 想定プロジェクトとバックエンド言語

| # | モチーフ | Backend | 主な学習テーマ（一言） |
| --- | --- | --- | --- |
| 1 | Slack | Rails | WS / fan-out |
| 2 | YouTube | Rails | 非同期・状態機械 |
| 3 | GitHub | Rails | 権限グラフ |
| 4 | Instagram | Django/DRF | タイムライン・ORM |
| 5 | Reddit | FastAPI | 非同期・コメントツリー |
| 6 | Uber | Go | 並行・空間索引 |
| 7 | Discord | Go | WS fan-out・シャーディング |

機能詳細・ai-worker 役割は policy。LLM 本体は方針どおり **ローカル完結・モック可**。

---

## 共通ドキュメント（`docs/`）

コーディング規約・Git・テスト等：[`docs/coding-rules/`](docs/coding-rules/)、[`docs/git-workflow.md`](docs/git-workflow.md)、[`docs/testing-strategy.md`](docs/testing-strategy.md)、[`docs/api-style.md`](docs/api-style.md)
