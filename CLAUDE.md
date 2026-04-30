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

### 2. ディレクトリ構成

```txt
service-architecture-lab/
  projects/
    youtube/
    slack/
    github/
  infra/
    terraform/
```

### 3. 各プロジェクト内の構成はシンプルに開始

```txt
service-architecture-lab/
  projects/
    youtube/
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
* README にアーキテクチャ図と動作確認手順がまとまっている

> 機能網羅ではなく、**アーキテクチャ理解とローカルでの動作確認ができるレベル**を達成度の基準とする。

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
