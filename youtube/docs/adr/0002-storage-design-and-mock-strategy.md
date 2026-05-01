# ADR 0002: 動画ストレージ設計とモック戦略

## ステータス

Accepted（2026-05-01）

## コンテキスト

動画プラットフォームの本質的なコストとアーキテクチャは **オブジェクトストレージ + CDN** にある。
学習用ローカル環境ではこれを再現できないが、**本番化したらどう設計するかを示せる構造**にしておきたい。

制約：

- 外部 API 不可、ローカル完結
- 動画ファイルそのものは数百 MB〜GB 規模になり得るが、学習用は数十 MB のサンプルで十分
- 状態機械（ADR 0001）と整合する形で、アップロードと変換成果物を別物として扱いたい
- CI で扱える容量・サイズでなくてはならない

## 決定

**Active Storage の `:local` サービスをディスクに置き、本番化想定では S3 + CloudFront に置き換える設計図を Terraform で示す** を採用する。

- 開発: `config.active_storage.service = :local` → `youtube/backend/storage/` 配下
- 動画は `Video has_one_attached :original` と `has_one_attached :transcoded`
- サムネ画像も `has_one_attached :thumbnail`（ai-worker が生成）
- 本番想定: Terraform で S3 + CloudFront + 署名付き URL 方式を描くが apply はしない

## 検討した選択肢

### 1. Active Storage local + Terraform で S3 設計図 ← 採用

- 利点: Rails 標準、追加依存ゼロ、テストが速い
- 利点: 同じ API (`video.original.attach`) で本番では S3 アダプタに差し替えられる
- 欠点: ローカルディスクが本番想定と性質が違う（並行書き込み・整合性モデルが違う）

### 2. MinIO をローカルで立ててS3互換にする

- 利点: 本番に近い API 経路を再現できる
- 欠点: docker-compose に1サービス増える（Redis を切ったのに別物が増えると本末転倒）
- 欠点: 学習目的が "ストレージ設計" ではなく "状態機械" にあるのでオーバースペック

### 3. ファイルアップロードは扱わず、メタデータ + URL 入力のみ

- 利点: 一番シンプル
- 欠点: 「アップロード状態機械」の練習にならない（ADR 0001 と整合しない）

## 採用理由

- **学習価値**: Active Storage のアタッチメント API を体験 + 本番設計を Terraform で示す二段構えで、"設計図と実装の対応" が読める
- **アーキテクチャ妥当性**: 実プロダクトでも Rails アプリは Active Storage 経由で S3 を使うパターンが多い
- **責務分離**: ストレージ層の差し替えがアプリケーションコードを汚さない（service 設定のみで切り替え可）

## 却下理由

- MinIO: docker-compose の肥大化と学習目的のフォーカスずれ
- メタデータのみ: アップロード状態機械の素材にならない

## 引き受けるトレードオフ

- **本番との乖離**: 並行書き込み・大容量配信・Range リクエスト最適化はローカルでは扱わない（Terraform で示す）
- **CDN 効果なし**: 動画配信は backend が直接返すので遅い → 学習用なので許容
- **大容量テスト不可**: 数十 MB 程度のサンプルでパイプラインを回す。スケール検証は別の機会

## このADRを守るテスト / 実装ポインタ

- `youtube/backend/config/storage.yml` — `:local` service 定義
- `youtube/backend/app/models/video.rb` — `has_one_attached :original` / `:thumbnail`
- `youtube/infra/terraform/s3.tf` — 本番想定の S3 (`youtube-videos-*` / `youtube-thumbnails-*`)
- `youtube/infra/terraform/cloudfront.tf` — CDN 経由配信

## 関連 ADR

- ADR 0001: アップロードパイプラインの状態機械
- ADR 0004（予定）: 本番化想定 AWS 構成（S3 / CloudFront / ECS）
