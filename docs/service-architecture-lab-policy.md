# Service Architecture Lab — リポジトリ方針（詳細）

ルートの `CLAUDE.md` はエージェントの毎ターン文脈を抑えるため要約のみとし、判定・一覧の詳細は本書に記す。

---

## 完成の定義

各プロジェクトは以下を満たした時点で「完成」とする。

- ローカル環境（`docker compose up` 等）で全コンポーネントが起動する
- 主要ユースケースがブラウザ／クライアントから動作確認できる
- そのサービスが解いている技術課題のうち、対象としたものがコード上で読み取れる
- プロジェクト直下の README にアーキテクチャ図と動作確認手順がまとまっている
- リポジトリ root の `README.md` の「プロジェクト一覧」表に概要・技術課題・ステータスが追記されている
- 主要な設計判断が **ADR** として最低3本記録されている（後述）
- CI（GitHub Actions）でそのプロジェクトの lint / test ジョブが追加されている

> 機能網羅ではなく、**アーキテクチャ理解とローカルでの動作確認ができるレベル**を達成度の基準とする。

---

## ADR（アーキテクチャ決定記録）

設計判断は **ADR（Architecture Decision Record）** として残す。  
コードからは読み取れない「なぜそう設計したか」「何を比較して何を選ばなかったか」を記録する。

### 配置

```txt
<service>/docs/adr/
  0001-<決定の見出し>.md
  0002-<決定の見出し>.md
  ...
```

### 1ファイルのフォーマット

- **タイトル**：`ADR NNNN: <決定の見出し>`
- **ステータス**：Proposed / Accepted / Superseded by ADR NNNN
- **コンテキスト**：何を解こうとしているか、制約は何か
- **決定**：採用したアプローチ
- **検討した選択肢**：他に検討した案
- **採用理由 / 却下理由**：なぜこれを選んだか・他を選ばなかったか
- **引き受けるトレードオフ**：諦めたこと、技術的負債

### 運用ルール

- 1ファイル 50〜150 行を目安（長文ドキュメントにしない）
- 既存の決定を覆す場合は **既存 ADR を削除せず** Superseded にし、新しい ADR を起こす
- プロジェクトあたり **最低3本**：重要な分岐点を必ず3つ以上残す（例：配信方式 / ストレージ設計 / 整合性モデル）

雛形：`docs/adr-template.md`

---

## スコープの考え方

<a id="scope"></a>

判断基準：

> 「これを実装することで、サービス固有の技術課題に対する理解が深まるか？」  
> Yes → 含める / No → 除外

### 含める（技術課題の中核）

- WebSocket / Pub-Sub fan-out（リアルタイム配信）
- 非同期ワーカー・キュー（状態機械、通知配信）
- DB設計・権限グラフ
- 検索・レコメンドの責務分離（Rails ↔ ai-worker の境界）
- アップロード／CI ステータスのような状態遷移
- 認証の最小1経路

### 除外する（網羅しても学びが薄い・終わらない）

- UI の作り込み：絵文字ピッカー、リッチテキスト、アニメーション細部
- i18n / a11y の網羅
- 認証手段の網羅：OAuth各種、SAML、SSO、2FA → 1経路で十分
- 通知チャネルの網羅：メール / SMS / プッシュ / Webhook → 1経路で十分
- 管理画面の細部：ロール作成UI、監査ログ閲覧UI
- ビジネス機能：課金、サブスク、請求書、クーポン
- 運用周辺：A/Bテスト基盤、アナリティクス、フィーチャーフラグ管理
- 法令対応：GDPR削除フロー、データエクスポート網羅
- モバイル / デスクトップアプリ
- 実トラフィック向けの最適化（CDN チューニング、シャーディング等）  
  → Terraform で「設計図」としてのみ示す

### 判断例

| 機能 | 判定 | 理由 |
| --- | --- | --- |
| Slack の絵文字リアクション | 薄く含める | DB設計・リアルタイム反映の練習。網羅はしない |
| Slack のハドル（音声通話） | 除外 | WebRTC は別領域 |
| YouTube の動画変換パイプライン | 含める | 非同期×状態機械の典型例。実コーデックは使わずモックでOK |
| YouTube の収益化・広告挿入 | 除外 | ビジネス機能 |
| GitHub の Issue / PR 権限グラフ | 含める | 権限設計の中核 |
| GitHub の Marketplace / 課金 | 除外 | ビジネス機能 |

---

## 想定プロジェクト

### 1. Slack

- WebSocket通信、チャンネル、メッセージ、既読管理、通知、検索
- Python(ai-worker)：要約、メッセージ分析（モック）

### 2. YouTube

- 動画メタデータ管理、アップロード状態管理、コメント、検索
- Python(ai-worker)：レコメンド、タグ抽出、サムネ生成（モック）

### 3. GitHub

- Issue、Pull Request、レビュー、CIステータス管理
- Python(ai-worker)：コード解析（モック）、AIレビュー（モック）

### 4. Instagram（Python 主体 / Django）

> 例外的に **バックエンドを Python(Django) で実装** する。Django/DRF の実務感覚と、巨大スケール事例の追体験が目的。

- Backend（Django / DRF）：ユーザー/フォロー、投稿、タイムライン、いいね/コメント、認証（最小1経路）
- Python(ai-worker)：タイムライン生成（fan-out on write / read のいずれか）、レコメンド（モック）、画像タグ抽出（モック）
- 技術課題の中核：**タイムライン生成戦略**、フォローグラフの DB 設計、Django ORM の N+1 回避とインデックス

### 5. Reddit（Python 主体 / FastAPI）

> 例外的に **バックエンドを Python(FastAPI) で実装** する。

- Backend：サブレディット、投稿/コメント（ツリー）、投票、スコアリング（Hot/Top/New）、認証（最小1経路）
- Python(ai-worker)：ランキング再計算バッチ、スパム判定（モック）、関連サブレディット（モック）
- 技術課題の中核：**コメントツリーの DB 設計**、投票の整合性、ランキング（Hot/Best）

### 6. Uber（Go 主体）

> 例外的に **バックエンドを Go で実装** する。

- Backend：ドライバー位置更新、マッチング、配車状態機械、料金計算、認証（最小1経路）
- Python(ai-worker)：ETA（モック）、サージ（モック）、需要予測バッチ
- 技術課題の中核：**地理空間インデックス**、goroutine + channel、状態機械の整合性

### 7. Discord（Go 主体）

> 例外的に **バックエンドを Go で実装** する。

- Backend：ギルド/チャンネル/メッセージ、WebSocket fan-out、プレゼンス、ロール/権限、認証（最小1経路）
- Python(ai-worker)：要約（モック）、スパム/NSFW（モック）
- 技術課題の中核：**WebSocket fan-out** とギルド単位シャーディング、購読者管理、プレゼンス整合性

> Slack との棲み分け：こちらは **Go × ギルド単位シャーディング** に焦点。

---

## 学習方針：言語別と Rails リプレイス

<a id="learning-roadmap-rails-replace"></a>

オーナーは **Rails エンジニア** を主軸としつつ、Python / Go のナレッジ獲得を目的にプロジェクトを並走させる。

### 各プロジェクトの言語役割

| # | プロジェクト | バックエンド | 主な学習対象 |
| --- | --- | --- | --- |
| 1 | Slack | Rails | WebSocket / fan-out（Rails 視点） |
| 2 | YouTube | Rails | 非同期ワーカー / 状態機械 |
| 3 | GitHub | Rails | 権限グラフ / 状態管理 |
| 4 | Instagram | **Python(Django/DRF)** | Django ORM / タイムライン生成 |
| 5 | Reddit | **Python(FastAPI)** | 非同期 I/O / コメントツリー |
| 6 | Uber | **Go** | goroutine / 地理空間インデックス |
| 7 | Discord | **Go** | WebSocket fan-out / シャーディング |

### Rails リプレイス学習（オプション）

Python / Go で実装したプロジェクト（4〜7）は、**完成後に Rails で再実装する別ディレクトリ**を許容する。

```txt
service-architecture-lab/
  instagram/          # Django/DRF 版（オリジナル）
  instagram-rails/    # Rails 再実装版（学習用）
```

- 同じドメインを言語/FW 変えて実装し直し、差分を ADR に残す
- リプレイス版は **オリジナル完成後**に着手（同時並行しない）
- リプレイス版も完成の定義（ADR 最低3本・README・CI 等）は同じ

---

## インフラ設計（任意）

Terraform で以下を定義する（**実行はしない**）：VPC、ECS/Lambda、RDS、ElastiCache、S3、SQS、CloudFront、ALB、IAM、CloudWatch。

目的：本番化するならどう設計するかを「設計図」として示す。

---

## `docs/` の索引（共通ルール）

走りながら整備する。既存・想定：

- `docs/coding-rules/frontend.md` — React / Next.js
- `docs/coding-rules/rails.md` — Rails
- `docs/coding-rules/python.md` — Python: (A) ai-worker / (B) Django / (C) FastAPI async backend
- `docs/coding-rules/go.md` — Go (discord で確立)
- `docs/git-workflow.md` — ブランチ・コミット・PR
- `docs/testing-strategy.md` — テスト方針 (Rails RSpec / Django pytest / FastAPI async pytest / Go race / Playwright)
- `docs/adr-template.md` — ADR 雛形
- `docs/api-style.md` — API スタイル
- `docs/operating-patterns.md` — 横断パターン (graceful degradation / 内部 ingress / fan-out / Hub / Materialized Path / 相対加算 + reconcile / APScheduler)
- `docs/framework-django-vs-rails.md` — Django ↔ Rails 比較
- `docs/framework-python-async-vs-sync.md` — Django sync vs FastAPI async (Python 二大潮流)

プロジェクト固有のアーキ図・ADR は `<service>/docs/` 配下。
