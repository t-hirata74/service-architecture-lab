# Service Architecture Lab 設計方針まとめ

## 概要

本リポジトリは、有名なSaaS・Webサービスのアーキテクチャを参考にしながら、  
ローカル環境で動作するミニマムな構成を再現し、設計理解と技術力向上を目的とした検証用プロジェクト群です。

---

## 目的

- アーキテクチャ理解の深化
- Frontend(React, Next.js)と、Backend(Ruby,Python)の実践的スキル獲得
- Railsとの組み合わせによる実務的構成の検証
- AI/データ処理を含むシステム設計力の向上
- GitHub上でのポートフォリオ強化

---

## 基本方針

### 1. 外部APIは使用しない

- すべてローカル環境で完結
- モック・ダミーデータを使用
- 外部サービス依存を排除

---

### 2. ディレクトリ構成例

```txt
service-architecture-lab/
  slack/
  youtube/
  github/
  docs/        # 共通ルール・コーディング規約・テスト戦略など
  infra/
    terraform/
```

### 3. 各プロジェクト内の構成はシンプルに開始

```txt
service-architecture-lab/
  slack/
    frontend/
    backend/    (Rails)
    ai-worker/  (Python)
    docs/
    docker-compose.yml
    README.md
    infra/
      terraform/
```

※ Terraformは実行しないが設計図として用途

---

### 4. 技術役割の分離

#### Frontend（React / Next.js）

* UI / UX 実装（ページ・コンポーネント）
* ルーティング・画面遷移（App Router 想定）
* SSR / CSR / ISR の使い分け検証
* 認証セッションの保持と API 呼び出し
* リアルタイム購読（WebSocket / SSE）の購読層
* クライアント状態管理（必要に応じて Zustand / TanStack Query 等）
* Rails / ai-worker への BFF 的な接続点

#### Rails（backend）

* 認証
* CRUD API
* DB設計
* 権限管理
* 管理機能
* GraphQL / REST
* アプリケーションロジック

#### Python（ai-worker）

* AI処理（モック含む）
* レコメンド
* 検索ランキング
* テキスト処理
* バッチ処理
* 非同期ワーカー

---

## 完成の定義

各プロジェクトは以下を満たした時点で「完成」とする。

* ローカル環境（`docker compose up` 等）で全コンポーネントが起動する
* 主要ユースケースがブラウザ／クライアントから動作確認できる
* そのサービスが解いている技術課題のうち、対象としたものがコード上で読み取れる
* プロジェクト直下の README にアーキテクチャ図と動作確認手順がまとまっている
* リポジトリ root の `README.md` の「プロジェクト一覧」表に概要・技術課題・ステータスが追記されている
* 主要な設計判断が **ADR** として最低3本記録されている（後述）
* CI（GitHub Actions）でそのプロジェクトの lint / test ジョブが追加されている

> 機能網羅ではなく、**アーキテクチャ理解とローカルでの動作確認ができるレベル**を達成度の基準とする。

---

## ADR（アーキテクチャ決定記録）

設計判断は **ADR（Architecture Decision Record）** として残す。  
コードからは読み取れない「なぜそう設計したか」「何を比較して何を選ばなかったか」を記録することで、半年後の自分・他者・採用担当者にも設計意図が伝わる状態にする。

### 配置

```txt
<service>/docs/adr/
  0001-<決定の見出し>.md
  0002-<決定の見出し>.md
  ...
```

### 1ファイルのフォーマット

* **タイトル**：`ADR NNNN: <決定の見出し>`
* **ステータス**：Proposed / Accepted / Superseded by ADR NNNN
* **コンテキスト**：何を解こうとしているか、制約は何か
* **決定**：採用したアプローチ
* **検討した選択肢**：他に検討した案
* **採用理由 / 却下理由**：なぜこれを選んだか・他を選ばなかったか
* **引き受けるトレードオフ**：諦めたこと、技術的負債

### 運用ルール

* 1ファイル 50〜150 行を目安（長文ドキュメントにしない）
* 既存の決定を覆す場合は **既存 ADR を削除せず** Superseded にし、新しい ADR を起こす
* プロジェクトあたり **最低3本**：重要な分岐点を必ず3つ以上残す  
  例：配信方式 / ストレージ設計 / 整合性モデル など

---

## スコープの考え方

判断基準：

> 「これを実装することで、サービス固有の技術課題に対する理解が深まるか？」  
> Yes → 含める / No → 除外

### 含める（技術課題の中核）

* WebSocket / Pub-Sub fan-out（リアルタイム配信）
* 非同期ワーカー・キュー（状態機械、通知配信）
* DB設計・権限グラフ
* 検索・レコメンドの責務分離（Rails ↔ ai-worker の境界）
* アップロード／CI ステータスのような状態遷移
* 認証の最小1経路

### 除外する（網羅しても学びが薄い・終わらない）

* UI の作り込み：絵文字ピッカー、リッチテキスト、アニメーション細部
* i18n / a11y の網羅
* 認証手段の網羅：OAuth各種、SAML、SSO、2FA → 1経路で十分
* 通知チャネルの網羅：メール / SMS / プッシュ / Webhook → 1経路で十分
* 管理画面の細部：ロール作成UI、監査ログ閲覧UI
* ビジネス機能：課金、サブスク、請求書、クーポン
* 運用周辺：A/Bテスト基盤、アナリティクス、フィーチャーフラグ管理
* 法令対応：GDPR削除フロー、データエクスポート網羅
* モバイル / デスクトップアプリ
* 実トラフィック向けの最適化（CDN チューニング、シャーディング等）  
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

* WebSocket通信
* チャンネル
* メッセージ
* 既読管理
* 通知
* 検索

Python側：

* 要約
* メッセージ分析（モック）

---

### 2. YouTube

* 動画メタデータ管理
* アップロード状態管理
* コメント
* 検索

Python側：

* レコメンド
* タグ抽出
* サムネ生成（モック）

---

### 3. GitHub

* Issue
* Pull Request
* レビュー
* CIステータス管理

Python側：

* コード解析（モック）
* AIレビュー（モック）

---

### 4. Instagram（Python 主体 / Django）

> 例外的に **バックエンドを Python(Django) で実装** する。Django/DRF の実務感覚と、巨大スケール事例（実際の Instagram は Django ベース）の追体験が目的。

Backend（Django / DRF）：

* ユーザー / フォロー関係（有向グラフ）
* 投稿（画像メタデータ・キャプション）
* タイムライン（フォロー中ユーザーの投稿フィード）
* いいね / コメント
* 認証（最小1経路）

Python(ai-worker)：

* タイムライン生成（fan-out on write / read のどちらかを検証）
* レコメンド（発見タブ相当・モック）
* 画像タグ抽出（モック）

技術課題の中核：

* **タイムライン生成戦略**（push 型 vs pull 型）
* フォローグラフの DB 設計
* Django ORM での N+1 回避とインデックス設計

---

### 5. Reddit（Python 主体 / FastAPI）

> 例外的に **バックエンドを Python(FastAPI) で実装** する。FastAPI + 非同期 I/O + Pydantic の実務感覚を獲得することが目的。

Backend（FastAPI）：

* サブレディット（コミュニティ）
* 投稿 / コメント（**ツリー構造**）
* Upvote / Downvote
* スコアリング（Hot / Top / New）
* 認証（最小1経路）

Python(ai-worker)：

* ランキング再計算バッチ（Hot スコアの定期更新）
* スパム判定（モック）
* 関連サブレディットレコメンド（モック）

技術課題の中核：

* **コメントツリーの DB 設計**（Adjacency List / Materialized Path / Nested Set の比較）
* 投票スコアのリアルタイム反映と整合性
* ランキングアルゴリズム（Hot/Best）の実装

---

### 6. Uber（Go 主体 / 配車マッチング）

> 例外的に **バックエンドを Go で実装** する。goroutine による高並行処理と、地理空間インデックスを用いたリアルタイムマッチングを学ぶことが目的。

Backend（Go）：

* ドライバー位置の継続更新（WebSocket / gRPC streaming）
* 乗車リクエストとドライバーのマッチング
* 配車状態の状態機械（requested → matched → on_trip → completed）
* 料金計算（距離 × 時間 × サージ係数）
* 認証（最小1経路）

Python(ai-worker)：

* ETA 推定（モック）
* サージプライシング推定（モック）
* 需要予測バッチ

技術課題の中核：

* **地理空間インデックス**（S2 / Geohash / H3 のいずれかで近傍検索）
* goroutine + channel による並行マッチングループ
* 状態機械の整合性（重複マッチ防止）

---

### 7. Discord（Go 主体 / リアルタイムチャット）

> 例外的に **バックエンドを Go で実装** する。WebSocket fan-out とサーバ／チャンネル単位のシャーディングを学ぶことが目的。

Backend（Go）：

* ギルド（サーバ）／チャンネル／メッセージ
* WebSocket ゲートウェイ（pub/sub fan-out）
* プレゼンス（オンライン状態）
* ロール／権限（チャンネル単位の overwrite）
* 認証（最小1経路）

Python(ai-worker)：

* メッセージ要約（モック）
* スパム／NSFW 検知（モック）

技術課題の中核：

* **WebSocket fan-out** とギルド単位のシャーディング設計
* goroutine + channel での購読者管理
* プレゼンス情報の整合性（ハートビート設計）

> Slack プロジェクトと用途が近いが、こちらは **Go × ギルド単位シャーディング** に焦点を置き、Slack(Rails) との実装比較を学習素材にする。

---

## 学習方針：言語別プロジェクトと Rails リプレイス

本リポジトリのオーナーは **Rails エンジニア** を主軸としつつ、Python / Go のナレッジ獲得を目的に上記プロジェクトを並走させる。

### 各プロジェクトの言語役割（再掲）

| # | プロジェクト | バックエンド | 主な学習対象 |
| --- | --- | --- | --- |
| 1 | Slack | Rails | WebSocket / fan-out（Rails 視点） |
| 2 | YouTube | Rails | 非同期ワーカー / 状態機械 |
| 3 | GitHub | Rails | 権限グラフ / 状態管理 |
| 4 | Instagram | **Python(Django/DRF)** | Django ORM / タイムライン生成 |
| 5 | Reddit | **Python(FastAPI)** | 非同期 I/O / コメントツリー |
| 6 | Uber | **Go** | goroutine / 地理空間インデックス |
| 7 | Discord | **Go** | WebSocket fan-out / シャーディング |

### Rails リプレイス学習

Python / Go で実装したプロジェクト（4〜7）は、**完成後に Rails で再実装する別プロジェクト**を作ることを学習オプションとして許容する。

```txt
service-architecture-lab/
  instagram/          # Django/DRF 版（オリジナル）
  instagram-rails/    # Rails 再実装版（学習用リプレイス）
```

目的：

* 同じドメインを **言語/FW を変えて実装し直す**ことで、各 FW の思想・ORM・非同期モデルの違いを体感する
* Rails への置き換え時に「Django/FastAPI/Go の何が代替しづらいか」を ADR に残す（例：Django Admin、FastAPI の型駆動、Go の並行性 など）
* リプレイス版は **オリジナル版の完成後に着手**する。同時並行で進めない（混乱と未完を避ける）

リプレイス版でも ADR 最低3本・README・CI 追加など「完成の定義」は同じ基準を満たすこと。

---

## インフラ設計（任意）

Terraformで以下を定義（実行はしない）

* VPC
* ECS / Lambda
* RDS
* ElastiCache
* S3
* SQS
* CloudFront
* ALB
* IAM
* CloudWatch

目的：

> 「本番化するならどう設計するか」を示す

---

## 関連ドキュメント

詳細なルールは `docs/` 配下に分割して配置する。  
**走りながら整備する方針**（最初のプロジェクト着手時から必要になったものを書き起こしていく）。

想定する分割：

* `docs/coding-rules/frontend.md` — React / Next.js のコーディング規約
* `docs/coding-rules/rails.md` — Rails のコーディング規約
* `docs/coding-rules/python.md` — Python (ai-worker) のコーディング規約
* `docs/git-workflow.md` — ブランチ戦略・コミット規約・PR運用
* `docs/testing-strategy.md` — テスト方針（単体 / 結合 / E2E）
* `docs/adr-template.md` — ADR の雛形

プロジェクト固有のアーキ図・ADR は `<service>/docs/` 配下に配置する。
