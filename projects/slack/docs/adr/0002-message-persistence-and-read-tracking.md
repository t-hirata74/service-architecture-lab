# ADR 0002: メッセージ永続化と既読管理の整合性モデル

## ステータス

Accepted（2026-04-30）

## コンテキスト

Slack 風チャットでは以下の2つの設計判断が密接に関連する：

1. **メッセージの永続化スキーマ**：単一テーブルか、チャンネル単位パーティションか、本文を JSONB か typed column か
2. **既読管理の整合性モデル**：誰が・どこまで読んだかをどう保存し、どう同期するか

特に既読管理は「全員 × 全メッセージ」のナイーブ実装が容易にスケール破綻するため、設計の筋を最初に通す必要がある。  
本プロジェクトはローカル完結だが、「Slack 規模を想定したらどうあるべきか」を学習対象に含める。

## 決定

以下を採用する。

### 1. メッセージは単一テーブル

```text
messages
  id                bigint (auto-increment、チャンネル横断で単調増加)
  channel_id        bigint (FK)
  user_id           bigint (FK)
  parent_message_id bigint (FK, nullable, スレッド用)
  body              text
  created_at        timestamptz
  edited_at         timestamptz (nullable)
  deleted_at        timestamptz (nullable, ソフトデリート)
  index (channel_id, id)         -- チャンネル内タイムライン取得用
  index (parent_message_id)      -- スレッド取得用
```

物理パーティションは取らない。学習目的としては「将来的に channel_id でパーティションする余地がある」と ADR で言及するに留める。

### 2. 既読は per-membership の cursor 方式

```text
memberships
  id                       bigint
  user_id                  bigint
  channel_id               bigint
  joined_at                timestamptz
  last_read_message_id     bigint (nullable)
  last_read_at             timestamptz (nullable)
  role                     enum (member / admin)
  unique (user_id, channel_id)
```

未読件数は次で算出：

```sql
SELECT count(*) FROM messages
WHERE channel_id = :channel_id
  AND id > :last_read_message_id
  AND deleted_at IS NULL;
```

### 3. 既読更新は eventually consistent + 単調増加ガード

- **クライアント側**：チャンネル閲覧中、画面に表示された最新メッセージIDを 500ms デバウンスして POST `/channels/:id/read` で送信
- **サーバー側**：`last_read_message_id` は **既存値より大きい場合のみ更新**（巻き戻り防止）
- **マルチデバイス同期**：更新成功時に ActionCable のユーザー専用チャンネルへ broadcast し、他デバイスの UI を更新

## 検討した選択肢

### 永続化スキーマ

| 案 | 評価 |
| --- | --- |
| **単一 messages テーブル** ← 採用 | シンプル。学習対象として索引・クエリチューニングを学べる |
| channel_id でテーブル分割 | スケール時の選択肢だが、ローカル検証では過剰。マイグレーション複雑化 |
| 本文を JSONB | 添付・リッチテキスト等の拡張性は高いが、まず text で開始し、必要時に JSONB カラムを追加する方が学習段階に合う |

### 既読管理

| 案 | 評価 |
| --- | --- |
| **per-membership cursor (last_read_message_id)** ← 採用 | O(users × channels)。Slack の実設計に近い |
| per-message read receipts (`read_receipts(user_id, message_id)`) | 「誰が読んだか」を per メッセージ表示できるが O(users × messages) で肥大化。LINE 型 UI が必要なら採用するが、Slack 風 UI には過剰 |
| Redis 上の counter のみ | 永続化が無く、再起動で既読が飛ぶ。学習目的でも不採用 |

### 整合性モデル

| 案 | 評価 |
| --- | --- |
| **eventually consistent + 単調増加ガード** ← 採用 | 書き込み頻度を抑えられる。既読は強整合不要なドメイン |
| 強整合（メッセージ表示の都度同期 POST） | 表示ごとに書き込み発生。負荷が高く、得るものが少ない |
| 楽観ロック / バージョン番号 | 既読は最終的に「進んだ位置」だけが意味を持つので過剰 |

## 採用理由

- **Slack の実設計と整合**：cursor 方式は公開されている Slack のアーキテクチャ解説と一致しており、再現対象として妥当
- **ナイーブ実装の罠を学べる**：「全員 × 全メッセージ」の receipts 方式と比較することで、データモデル設計の感覚が身につく
- **整合性ドメインの判断練習**：既読は「強整合性が要らないドメイン」の典型。何を犠牲にして何を取るかの判断軸を ADR として残す価値がある
- **マルチデバイス同期の実装練習**：ActionCable のユーザー専用チャンネル設計を実装する自然な動機になる

## 引き受けるトレードオフ

- **per-メッセージの既読インジケーターは出せない**：LINE のような「既読 3」表示は不可。Slack も DM 以外では同等。要件外として割り切る
- **クライアント不正に弱い**：クライアントが任意の `message_id` を送れる。サーバー側で「そのメッセージが該当チャンネルに存在するか」「ユーザーが該当チャンネルメンバーか」を検証して防御する
- **未読件数の取得が SQL count に依存**：チャンネルが極端に巨大化した場合は遅くなる。学習段階では実装し、スケール時は Redis でカウンタ化する選択肢を ADR 0xxx で別途扱う
- **削除メッセージの扱い**：ソフトデリートを採用するため、未読件数計算で `deleted_at IS NULL` を忘れるとズレる。リポジトリ層に一元化する
- **編集時の再通知有無**：本 ADR では扱わない。別 ADR で扱う

## 関連 ADR

- ADR 0001: リアルタイム配信方式（ActionCable + Redis Pub/Sub）
- ADR 0003（予定）: チャンネル / DM の権限モデル

## 参考にした考え方

- 既読 cursor 方式：Slack / Discord / Mattermost 等で共通する設計
- 単調増加ガード：分散ストレージにおける LWW（Last-Write-Wins）の応用
