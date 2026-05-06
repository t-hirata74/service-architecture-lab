# ADR 横断インデックス

9 サービスの ADR を **テーマ別** と **サービス別** の 2 軸で索引化したもの。

ADR は「コードからは読めない設計判断の理由」を残すための文書で、書式は [`adr-template.md`](adr-template.md) に従う。本リポでは各サービス最低 3 本を完成基準にしている（[完成の定義](service-architecture-lab-policy.md)）。

**累計: 40 本 / 9 サービス**

---

## 1. テーマ別（同じ問題を別の形で解いた経験を読みたい場合）

### 1.1 リアルタイム / streaming

WebSocket / SSE / polling / fan-out 構造の選定。

| ADR | サービス | タイトル |
| --- | --- | --- |
| [slack/0001](../slack/docs/adr/0001-realtime-delivery-method.md) | slack | リアルタイムメッセージ配信方式の選定（ActionCable + Redis を選択） |
| [perplexity/0003](../perplexity/docs/adr/0003-sse-streaming.md) | perplexity | ストリーミングプロトコルとして SSE を採用 |
| [discord/0001](../discord/docs/adr/0001-guild-sharding-single-process-hub.md) | discord | ギルド単位シャーディング + 単一プロセス Hub |
| [discord/0002](../discord/docs/adr/0002-hub-goroutine-channel-pattern.md) | discord | Hub の goroutine + channel 実装パターン |
| [discord/0003](../discord/docs/adr/0003-presence-heartbeat.md) | discord | プレゼンスのハートビート設計 |

### 1.2 整合性 / 同時実行制御

楽観/悲観ロック / 条件付き UPDATE / denormalized cache の整合性。

| ADR | サービス | タイトル |
| --- | --- | --- |
| [youtube/0001](../youtube/docs/adr/0001-upload-pipeline-state-machine.md) | youtube | 動画アップロードパイプラインの状態機械（Solid Queue + 同一トランザクション） |
| [shopify/0003](../shopify/docs/adr/0003-inventory-conditional-update-decrement.md) | shopify | 在庫の同時減算整合性 — 条件付き UPDATE + ledger |
| [reddit/0002](../reddit/docs/adr/0002-vote-integrity.md) | reddit | 投票の整合性と score の denormalize（truth + 相対加算 + reconcile） |
| [slack/0002](../slack/docs/adr/0002-message-persistence-and-read-tracking.md) | slack | メッセージ永続化と既読管理の整合性モデル |

### 1.3 認可モデル

権限グラフ / マルチテナント / ポリシーオブジェクトの配置。

| ADR | サービス | タイトル |
| --- | --- | --- |
| [github/0002](../github/docs/adr/0002-permission-graph.md) | github | 権限グラフのモデリング（PermissionResolver + Pundit の 2 層） |
| [shopify/0002](../shopify/docs/adr/0002-multi-tenancy-row-level-shop-scoping.md) | shopify | マルチテナント分離 — `shop_id` row-level scoping |
| [shopify/0004](../shopify/docs/adr/0004-app-platform-webhook-delivery.md) | shopify | App プラットフォーム — Webhook 配信（HMAC + scope 認可） |

### 1.4 認証

セッション / トークン / Bearer の選定。複数サービスで意図的に違う方式を試している。

| ADR | サービス | タイトル |
| --- | --- | --- |
| [slack/0004](../slack/docs/adr/0004-authentication-strategy.md) | slack | rodauth-rails + JWT |
| [perplexity/0007](../perplexity/docs/adr/0007-auth-rodauth-jwt-bearer.md) | perplexity | rodauth-rails + JWT bearer |
| [reddit/0004](../reddit/docs/adr/0004-async-stack-fastapi.md) | reddit | FastAPI + HS256 JWT（async スタック選定と同梱） |
| [instagram/0004](../instagram/docs/adr/0004-auth-drf-token.md) | instagram | DRF TokenAuthentication（1 経路） |
| [discord/0004](../discord/docs/adr/0004-auth-jwt-bearer.md) | discord | JWT bearer / WebSocket query param |

### 1.5 データモデル

ドメインのモデリング / グラフ構造 / 正規化判断。

| ADR | サービス | タイトル |
| --- | --- | --- |
| [github/0003](../github/docs/adr/0003-issue-pr-data-model.md) | github | Issue / Pull Request / Review のデータモデル（番号空間共有） |
| [instagram/0001](../instagram/docs/adr/0001-timeline-fanout-on-write.md) | instagram | タイムライン生成戦略（fan-out on write） |
| [instagram/0002](../instagram/docs/adr/0002-follow-graph.md) | instagram | フォローグラフの DB 設計 |
| [reddit/0001](../reddit/docs/adr/0001-comment-tree-storage.md) | reddit | コメントツリーの DB 設計（Adjacency List + Materialized Path） |
| [perplexity/0006](../perplexity/docs/adr/0006-chunk-strategy.md) | perplexity | チャンク分割戦略 |

### 1.6 検索 / 取得

全文検索 / hybrid retrieval / RAG パイプライン。

| ADR | サービス | タイトル |
| --- | --- | --- |
| [youtube/0004](../youtube/docs/adr/0004-database-and-search-strategy.md) | youtube | データベース選定と検索戦略（MySQL FULLTEXT ngram） |
| [perplexity/0001](../perplexity/docs/adr/0001-rag-pipeline-decomposition.md) | perplexity | RAG パイプラインの分割方式（retrieve / extract / synthesize） |
| [perplexity/0002](../perplexity/docs/adr/0002-hybrid-retrieval.md) | perplexity | Hybrid retrieval（BM25 + 擬似ベクタ類似度） |

### 1.7 境界 / モジュラリティ

サービス内 / サービス間の責務分離と依存方向。

| ADR | サービス | タイトル |
| --- | --- | --- |
| [shopify/0001](../shopify/docs/adr/0001-modular-monolith-rails-engine.md) | shopify | モジュラーモノリス — Rails Engine + packwerk |
| [youtube/0003](../youtube/docs/adr/0003-recommendation-boundary.md) | youtube | レコメンド機能の責務分離（Rails ↔ ai-worker） |
| [perplexity/0004](../perplexity/docs/adr/0004-citation-verification-boundary.md) | perplexity | 引用整合性の検証境界 |
| [github/0004](../github/docs/adr/0004-ci-status-aggregation.md) | github | CI ステータスの集約方式（ai-worker → 内部 ingress → GraphQL） |

### 1.8 キュー / 非同期 / バッチ

ジョブ基盤の選定と「同期で十分か」の判断。

| ADR | サービス | タイトル |
| --- | --- | --- |
| [reddit/0003](../reddit/docs/adr/0003-hot-ranking-batch.md) | reddit | Hot ランキングアルゴリズムと再計算バッチ（ai-worker APScheduler） |
| [shopify/0004](../shopify/docs/adr/0004-app-platform-webhook-delivery.md) | shopify | Webhook 配信（at-least-once + Solid Queue + idempotency） |
| [youtube/0001](../youtube/docs/adr/0001-upload-pipeline-state-machine.md) | youtube | Solid Queue + 同一トランザクションでの状態機械駆動 |

### 1.9 API スタイル

REST + OpenAPI / GraphQL / SSE の使い分け。横断方針は [`api-style.md`](api-style.md)。

| ADR | サービス | タイトル |
| --- | --- | --- |
| [github/0001](../github/docs/adr/0001-graphql-adoption.md) | github | API スタイルとして GraphQL を採用 |
| [youtube/0005](../youtube/docs/adr/0005-no-api-versioning.md) | youtube | API バージョニング (`/api/v1`) を採用しない |
| [perplexity/0003](../perplexity/docs/adr/0003-sse-streaming.md) | perplexity | SSE をストリーミングプロトコルとして採用 |

### 1.10 永続化 / ストレージ

DB 選定 / オブジェクトストレージのモック戦略。

| ADR | サービス | タイトル |
| --- | --- | --- |
| [slack/0003](../slack/docs/adr/0003-database-choice.md) | slack | データベースに MySQL を採用 |
| [youtube/0002](../youtube/docs/adr/0002-storage-design-and-mock-strategy.md) | youtube | 動画ストレージ設計とモック戦略 |
| [youtube/0004](../youtube/docs/adr/0004-database-and-search-strategy.md) | youtube | データベース選定と検索戦略 |

### 1.11 テスト / E2E

| ADR | サービス | タイトル |
| --- | --- | --- |
| [perplexity/0005](../perplexity/docs/adr/0005-testing-strategy.md) | perplexity | テスト戦略（pytest + httpx ASGITransport + dependency_overrides） |
| [slack/0005](../slack/docs/adr/0005-browser-e2e-with-playwright.md) | slack | ブラウザ E2E に Playwright を採用 |

### 1.12 言語 / フレームワーク選定

スタック自体を選ぶ判断（多くは「なぜ別の選択肢でないか」の対比を含む）。

| ADR | サービス | タイトル |
| --- | --- | --- |
| [reddit/0004](../reddit/docs/adr/0004-async-stack-fastapi.md) | reddit | 非同期 I/O スタック（FastAPI + SQLAlchemy 2.0 async + aiomysql） |
| [discord/0002](../discord/docs/adr/0002-hub-goroutine-channel-pattern.md) | discord | Go の goroutine + channel CSP パターン |

### 1.13 インフラ / 本番想定

`infra/terraform/` での設計図（apply はしない方針）。

| ADR | サービス | タイトル |
| --- | --- | --- |
| [slack/0006](../slack/docs/adr/0006-production-aws-architecture.md) | slack | AWS（ECS Fargate + Aurora） |
| [youtube/0006](../youtube/docs/adr/0006-production-aws-architecture.md) | youtube | AWS（ECS Fargate + Aurora MySQL + S3/CloudFront） |

---

## 2. サービス別（特定サービスの設計判断を時系列で読みたい場合）

### slack — Slack 風リアルタイムチャット (Rails)

主要技術課題: WebSocket fan-out / 既読 cursor 整合性 / Rails ↔ Python 境界

1. [0001 リアルタイム配信方式](../slack/docs/adr/0001-realtime-delivery-method.md)
2. [0002 メッセージ永続化と既読管理](../slack/docs/adr/0002-message-persistence-and-read-tracking.md)
3. [0003 データベース選定 (MySQL)](../slack/docs/adr/0003-database-choice.md)
4. [0004 認証方式 (rodauth-rails + JWT)](../slack/docs/adr/0004-authentication-strategy.md)
5. [0005 ブラウザ E2E (Playwright)](../slack/docs/adr/0005-browser-e2e-with-playwright.md)
6. [0006 本番 AWS アーキテクチャ](../slack/docs/adr/0006-production-aws-architecture.md)

### youtube — YouTube 風動画プラットフォーム (Rails)

主要技術課題: 非同期動画変換 / 状態機械 / FULLTEXT ngram 検索 / Rails ↔ Python 境界

1. [0001 アップロードパイプラインの状態機械](../youtube/docs/adr/0001-upload-pipeline-state-machine.md)
2. [0002 動画ストレージ設計とモック戦略](../youtube/docs/adr/0002-storage-design-and-mock-strategy.md)
3. [0003 レコメンドの責務分離](../youtube/docs/adr/0003-recommendation-boundary.md)
4. [0004 データベース選定と検索戦略](../youtube/docs/adr/0004-database-and-search-strategy.md)
5. [0005 API バージョニングを採用しない](../youtube/docs/adr/0005-no-api-versioning.md)
6. [0006 本番 AWS アーキテクチャ](../youtube/docs/adr/0006-production-aws-architecture.md)

### github — GitHub 風 Issue Tracker (Rails)

主要技術課題: 権限グラフ / Issue・PR モデル / GraphQL field 認可 / CI ステータス集約

1. [0001 GraphQL 採用](../github/docs/adr/0001-graphql-adoption.md)
2. [0002 権限グラフのモデリング](../github/docs/adr/0002-permission-graph.md)
3. [0003 Issue / PR / Review データモデル](../github/docs/adr/0003-issue-pr-data-model.md)
4. [0004 CI ステータスの集約方式](../github/docs/adr/0004-ci-status-aggregation.md)

### perplexity — Perplexity 風 RAG 検索 (Rails + ai-worker)

主要技術課題: RAG パイプライン / Hybrid retrieval / SSE 三段階 degradation / 引用整合性

1. [0001 RAG パイプライン分割](../perplexity/docs/adr/0001-rag-pipeline-decomposition.md)
2. [0002 Hybrid retrieval](../perplexity/docs/adr/0002-hybrid-retrieval.md)
3. [0003 SSE streaming](../perplexity/docs/adr/0003-sse-streaming.md)
4. [0004 引用整合性の検証境界](../perplexity/docs/adr/0004-citation-verification-boundary.md)
5. [0005 テスト戦略](../perplexity/docs/adr/0005-testing-strategy.md)
6. [0006 チャンク分割戦略](../perplexity/docs/adr/0006-chunk-strategy.md)
7. [0007 認証 (rodauth-rails JWT bearer)](../perplexity/docs/adr/0007-auth-rodauth-jwt-bearer.md)

### instagram — Instagram 風タイムライン (Django/DRF)

主要技術課題: fan-out on write / フォローグラフ / Django ORM N+1 / DRF TokenAuth

1. [0001 タイムライン生成 (fan-out on write)](../instagram/docs/adr/0001-timeline-fanout-on-write.md)
2. [0002 フォローグラフの DB 設計](../instagram/docs/adr/0002-follow-graph.md)
3. [0003 Django ORM N+1 と index 設計](../instagram/docs/adr/0003-orm-n-plus-one.md)
4. [0004 認証 (DRF TokenAuthentication)](../instagram/docs/adr/0004-auth-drf-token.md)

### discord — Discord 風リアルタイムチャット (Go)

主要技術課題: ギルド単位シャーディング / Hub CSP パターン / プレゼンス整合性 / WebSocket fan-out

1. [0001 ギルド単位シャーディング + 単一プロセス Hub](../discord/docs/adr/0001-guild-sharding-single-process-hub.md)
2. [0002 Hub の goroutine + channel パターン](../discord/docs/adr/0002-hub-goroutine-channel-pattern.md)
3. [0003 プレゼンスのハートビート設計](../discord/docs/adr/0003-presence-heartbeat.md)
4. [0004 認証方式 (JWT bearer)](../discord/docs/adr/0004-auth-jwt-bearer.md)

### reddit — Reddit 風 forum (FastAPI / async)

主要技術課題: コメントツリー / 投票整合性 / Hot ランキング / FastAPI async + SQLAlchemy 2.0 async

1. [0001 コメントツリーの DB 設計](../reddit/docs/adr/0001-comment-tree-storage.md)
2. [0002 投票整合性と score denormalize](../reddit/docs/adr/0002-vote-integrity.md)
3. [0003 Hot ランキングと再計算バッチ](../reddit/docs/adr/0003-hot-ranking-batch.md)
4. [0004 非同期 I/O スタック + JWT](../reddit/docs/adr/0004-async-stack-fastapi.md)

### shopify — Shopify 風 EC プラットフォーム (Rails 8)

主要技術課題: モジュラーモノリス / マルチテナント / 在庫整合性 / App プラットフォーム

1. [0001 モジュラーモノリス (Rails Engine + packwerk)](../shopify/docs/adr/0001-modular-monolith-rails-engine.md)
2. [0002 マルチテナント (`shop_id` row-level scoping)](../shopify/docs/adr/0002-multi-tenancy-row-level-shop-scoping.md)
3. [0003 在庫の同時減算整合性 (条件付き UPDATE + ledger)](../shopify/docs/adr/0003-inventory-conditional-update-decrement.md)
4. [0004 Webhook 配信 (at-least-once + HMAC + idempotency)](../shopify/docs/adr/0004-app-platform-webhook-delivery.md)

---

## 3. 索引の保守方針

- 新しい ADR を追加したら、**サービス別**節と該当する**テーマ別**節の両方に追記する
- ADR が "Superseded" になった場合は両節で取り消し線を引き、後継 ADR へリンクを張る
- テーマ分類は厳密でなく、最も主要な観点 1〜2 個に絞る（同じ ADR が 3 テーマに登場するのは可）
