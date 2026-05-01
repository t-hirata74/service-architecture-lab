# ADR 0006: 本番デプロイ先に AWS (ECS Fargate + Aurora MySQL + S3/CloudFront) を採用する

## ステータス

Accepted（2026-05-01）

## コンテキスト

CLAUDE.md は「Terraform は実行しないが設計図として用途」と定めており、本番化の
妥当性を **コードとして読める形**で示す必要がある。YouTube 風プロジェクトを
そのままクラウドにデプロイすると仮定したとき、構成の指針を ADR として残す。

要件：

- 3-AZ 高可用構成（学習目的でも HA 設計を見せる）
- ADR 0001（Solid Queue / Redis 不要）、ADR 0002（S3 + CloudFront）、
  ADR 0004（Aurora MySQL）と整合する
- Frontend (Next.js SSR)、Backend (Rails)、ai-worker (FastAPI) の 3 サービスを
  統一的にデプロイできる
- 動画ファイルは **大容量 + Range 配信** が想定される
- 本番化したら Solid Queue を SQS / 専用 worker に差し替える余地を残す

## 決定

**AWS 上に以下の構成で組む** ことを基本路線とする。実 apply はしない。

| レイヤー | 採用 |
| --- | --- |
| ネットワーク | VPC（10.0.0.0/16）、3-AZ public/private subnets、AZ ごと NAT |
| エッジ | CloudFront（動画配信 + 静的アセット） + ALB（HTTPS, path 振り分け） |
| アプリケーション | ECS Fargate × 3 サービス（frontend / backend / ai-worker）|
| サービス間通信 | Service Connect (`youtube.internal` namespace) |
| データ | Aurora MySQL (writer + reader 1) — Solid トリオ専用 DB はクラスタ内に分離 |
| ストレージ | S3 `youtube-videos-*` (原本) / `youtube-thumbnails-*` (CDN 配信元) |
| 非同期 | Solid Queue が初期。`sqs.tf` を予約として残し、SQS + 専用 worker に差し替え可能 |
| シークレット | Secrets Manager（DB password / Rails master key）|
| 観測 | CloudWatch Logs + 主要メトリクスのアラーム |

## 検討した選択肢

### 1. ECS Fargate + Aurora + S3/CloudFront ← 採用

- 利点: Slack プロジェクトと同パターン → 学習成果が一貫
- 利点: 動画配信の主役 (CloudFront + S3 Range) を素直に書ける
- 利点: Solid Queue / SQS の差し替えが Terraform の `sqs.tf` で示せる

### 2. ECS Fargate + RDS for MySQL + S3

- 利点: Aurora より安価 (~$30/mo)
- 欠点: HA / readreplica 設計の表現力が落ちる

### 3. EKS + Helm

- 利点: スケール時の柔軟性
- 欠点: 学習用にしては運用負荷が大きい / VPC や Pod IP 設計の議論が肥大化

## 採用理由

- **学習価値**: Slack プロジェクトと同じパターンを「動画ストレージ」「Solid Queue → SQS」のドメイン特性で書き換える練習になる
- **アーキテクチャ妥当性**: 中小〜中規模の動画系 SaaS でも一般的な構成
- **責務分離**: Solid Queue を本番で SQS に差し替える時、コードは Active Job アダプタの切替だけで済む（Terraform 側で SQS と DLQ の準備が完了している）

## 却下理由

- RDS for MySQL: HA を明示的に書きたいので Aurora 寄り
- EKS: スコープ過剰

## 引き受けるトレードオフ

- **Aurora のコスト**: dev 規模だと過剰。ただし「学習用に Terraform 上で示す」だけなので問題なし
- **Solid Queue → SQS 切替の二重化**: コード (Solid Queue) と Terraform (SQS) で書き分けが残る。これは ADR 0001 の引き受けトレードオフと一致
- **CloudFront のキャッシュ整合性**: Range リクエスト + Origin Shield 等の細部は本番で詰める

## このADRを守る成果物

- `youtube/infra/terraform/` の各 `.tf`（terraform validate を CI で通す）
- `youtube/infra/terraform/README.md` — ファイル分割と各ファイルの役割
- `.github/workflows/ci.yml` — `youtube-terraform` ジョブで `terraform fmt / validate`

## 関連 ADR

- ADR 0001: アップロード状態機械 + Solid Queue (本番では SQS 差し替え可)
- ADR 0002: ストレージ設計 (S3 + CloudFront)
- ADR 0004: DB 選定 + 検索戦略 (Aurora MySQL + FULLTEXT ngram)
