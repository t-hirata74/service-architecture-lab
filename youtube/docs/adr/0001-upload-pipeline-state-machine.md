# ADR 0001: 動画アップロードパイプラインの状態機械

## ステータス

Proposed（2026-04-30）

## コンテキスト

YouTube 風プロジェクトの中核技術課題は **「アップロードされた動画を非同期で変換し、状態を進める」** こと。
状態の取りうる値・遷移条件・失敗時のハンドリングを一貫して管理する必要がある。

制約：

- ローカル完結（外部 SaaS / 本物のコーデックは使わない）
- Slack で扱った WebSocket fan-out とは違う技術課題に焦点を当てたい
- 学習目的なので、本番では SQS / ECS タスクに置き換える前提の "ふり" ができる構造にしたい
- 状態遷移とビジネスデータ更新を **同一トランザクションで commit したい**（中途半端な状態を残さない）

## 決定

**`videos.status` を ENUM として永続化し、状態遷移は Solid Queue ジョブで駆動する** を採用する。

- 取りうる状態: `uploaded → transcoding → ready → published` (+ 失敗は `failed`、`failed → transcoding` で再試行可)
- 状態遷移は必ずモデルメソッド経由（`video.start_transcoding!` 等）で、内部でトランザクションを張る
- ジョブは Active Job + Solid Queue (database-backed)
- Solid Queue は **MySQL の queue 専用 DB** に enqueue する → `videos` テーブル更新と enqueue を **同じ MySQL トランザクション**で確定可能（multi-DB 跨ぎだが Rails 8 は同一接続プールで FOR UPDATE SKIP LOCKED が動く）

## 検討した選択肢

### 1. Solid Queue (Rails 8 デフォルト) ← 採用

- Redis 不要 → docker-compose が MySQL のみ
- DB トランザクション整合性が状態機械と相性がいい
- Rails 8 のデフォルト・Mission Control も同梱されている

### 2. Sidekiq + Redis

- 業界デファクト。情報量が圧倒的
- 欠点: enqueue とデータ更新が二重書き込み問題を起こしやすい（Redis が落ちた瞬間に DB 更新が先行して状態が orphan 化する）
- 欠点: Slack で既に Redis を扱っており、本リポジトリ内でのスタック重複

### 3. AWS SQS（本番想定）

- 本番ではこちら寄り
- ローカル開発体験が落ちる（LocalStack を入れるか実 SQS を叩く必要）
- → **Terraform 側 (infra/terraform) には SQS を描く**。コードは Solid Queue で実装し、設計図と実装の乖離は ADR 上で明示的に引き受ける

## 採用理由

- **学習価値**: Slack で Sidekiq+Redis をやらなかった分、Rails 8 の Solid トリオに触れる価値が高い
- **アーキテクチャ妥当性**: DB-driven Queue は Vitess + 同一クラスタ運用の Slack 等でも採用例があり、トランザクション整合性に強い
- **責務分離**: 状態遷移ロジックは Rails モデル、計算（変換のモック）はジョブクラス、配信は SSE と分離できる
- **将来の拡張性**: `Video` モデルの状態 ENUM はそのまま、ジョブのアダプタだけ Sidekiq / SQS に差し替え可能

## 却下理由

- Sidekiq + Redis: 二重書き込み問題、Slack とのスタック重複
- AWS SQS 直接: ローカル開発体験が劣化。本番設計は Terraform で示す方針

## 引き受けるトレードオフ

- **スループット上限**: 大量ジョブでは DB が先にボトルネックになる（学習用途では非問題）
- **本番想定との乖離**: コード (Solid Queue) と Terraform (SQS) で別物になる。ADR で明示することで合意済み扱いとする
- **モニタリング**: Mission Control を入れるか、最小は Rails console で確認

## このADRを守るテスト / 実装ポインタ（Phase 3 で確定）

- `youtube/backend/app/models/video.rb` — 状態 ENUM と遷移メソッド
- `youtube/backend/app/jobs/transcode_job.rb` — 失敗時の `failed` 遷移
- `youtube/backend/test/models/video_test.rb` — 不正遷移を弾くガード

## 関連 ADR

- ADR 0002: 動画ストレージ設計とモック戦略
- ADR 0003: レコメンド責務分離
- ADR 0004（予定）: アップロード進捗通知の配信方式（SSE 採用予定）
