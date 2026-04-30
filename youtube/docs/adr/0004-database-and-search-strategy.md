# ADR 0004: データベース選定と検索戦略

## ステータス

Proposed（2026-04-30）

## コンテキスト

YouTube 風プロジェクトの永続化要件：

- 動画メタデータ（タイトル / 説明 / タグ / 状態 / アップロード日時）
- コメント（動画ごと、ネスト1段は許容）
- ユーザー / 認証
- バックグラウンドジョブの状態（Solid Queue が使う）
- キャッシュ（Solid Cache が使う）
- リアルタイム配信用テーブル（Solid Cable が使う）

そして検索：

- 動画タイトル / 説明 / タグでの全文検索が欲しい
- 学習目的なので Elasticsearch まで導入する価値があるか要検討

制約：

- ローカル完結
- Slack で MySQL を採用済み（ADR 整合性）
- Solid トリオ採用 → DB 駆動なので DB 選定は重要

## 決定

**MySQL 8 を採用、検索は MySQL FULLTEXT (ngram parser) で開始** を採用する。

- DB: MySQL 8（utf8mb4 / ngram parser）
- 検索: `videos` テーブルに FULLTEXT インデックス（`title`, `description`）
- タグ検索は `tags` 中間テーブル経由で完全一致 + LIKE
- 全文検索の精度が学習対象になり始めた時点で別 ADR を起こし Elasticsearch を検討

## 検討した選択肢

### 1. MySQL 8 + FULLTEXT (ngram) ← 採用

- 利点: Slack と同じ DB エンジン、ngram で日本語 N-gram 全文検索が標準で動く
- 利点: Solid トリオも MySQL 上で完結
- 欠点: TF-IDF / BM25 の細かいランキング調整は弱い

### 2. PostgreSQL + pg_trgm / textsearch

- 利点: 全文検索性能・機能性は MySQL より上
- 欠点: Slack で MySQL を選んだ整合性が崩れる
- 欠点: Solid トリオは MySQL も Postgres もサポートだが移行コストの正当化が薄い

### 3. MySQL + Elasticsearch 同期

- 利点: 本物の検索エンジン体験
- 欠点: docker-compose に重量級サービス追加、整合性同期の責務が増える
- 欠点: 学習目的が "検索" ではなく "アップロード状態機械" にあるので過剰

## 採用理由

- **学習価値**: Slack で扱わなかった ngram 全文検索の練習ができる
- **アーキテクチャ妥当性**: 中規模サービスは MySQL FULLTEXT で十分回している実例多数
- **責務分離**: DB 1 個に集約できるので運用境界が単純
- **将来の拡張性**: スケール時に Elasticsearch 同期に移行する設計余地は残せる（CDC / Outbox パターン）

## 却下理由

- PostgreSQL: Slack との整合性メリットが大きい以上、切り替える理由が乏しい
- Elasticsearch: 学習フォーカスの観点で過剰。本番化想定として Terraform で言及するに留める

## 引き受けるトレードオフ

- **検索精度**: ランキングは粗い（タイトル一致重視の単純な順序）。本物の YouTube レベルではない
- **大規模時のボトルネック**: FULLTEXT は数百万行で性能劣化が出る。本番想定では別レイヤー
- **ngram の同義語処理なし**: シソーラス展開等は一切しない

## このADRを守るテスト / 実装ポインタ（Phase 5 で確定）

- `youtube/backend/db/migrate/*_add_fulltext_to_videos.rb` — ngram 指定の FULLTEXT
- `youtube/backend/app/controllers/searches_controller.rb` — クエリ組み立て
- `youtube/backend/test/integration/search_test.rb` — 検索結果の順序

## 関連 ADR

- ADR 0001: アップロード状態機械
- ADR 0003: レコメンド責務分離（検索とは別レイヤー）
- Slack ADR 0003（参照）: MySQL 採用の前例
