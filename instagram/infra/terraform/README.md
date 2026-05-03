# Instagram - Terraform 設計図 (本番想定)

CLAUDE.md の方針に従い **このディレクトリは Terraform を `apply` しない**。
あくまで「本番化するならどう設計するか」を示す設計図として `terraform fmt`
と `terraform validate` を CI で通すのが目的。

## 構成

| ファイル | 役割 |
| --- | --- |
| `versions.tf` | provider バージョン固定 + tag 設定 |
| `variables.tf` | region / VPC / domain / instance class などのパラメータ |
| `network.tf` | VPC / 3-AZ public / private (app / data) subnet / NAT Gateway |
| `security_groups.tf` | ALB / ECS frontend / backend / celery / ai-worker / RDS / Redis の SG |
| `alb.tf` | HTTPS listener、`/auth/*` `/posts*` 等を backend、それ以外を frontend に振り分け |
| `ecs.tf` | Fargate cluster + 4 service (frontend / backend / **celery worker** / ai-worker)、Service Discovery |
| `rds.tf` | Aurora MySQL writer + reader (ai-worker は reader_endpoint を使う) |
| `elasticache.tf` | Redis (Celery broker + 結果 backend、multi-AZ) |
| `s3.tf` | 画像保管 bucket (本リポは URL 文字列のみだが本番では pre-signed PUT 想定) |
| `cloudfront.tf` | ALB を origin にした CDN |
| `iam.tf` | execution role + 各 task role (frontend / backend / ai-worker) |
| `cloudwatch.tf` | ECS log group |
| `secrets.tf` | Secrets Manager (DJANGO_SECRET_KEY / DB password) |
| `outputs.tf` | ALB / CloudFront / RDS / Redis / S3 endpoint |

## 設計上の注記

- **ai-worker は reader_endpoint + read-only ユーザ**: ADR 0001 の責務分離
  (ai-worker は MySQL 読み専 / 書き込みは Django 経由のみ) を本番でも DB 層
  の権限で担保する。
- **Celery worker は ALB の inbound なし**: 純粋な job consumer。Redis broker
  と RDS のみ outbound。フォロー数の多いユーザの fan-out が増えるとここを
  scale-out する。
- **Redis の auth_token / transit encryption**: 派生 ADR で扱う余地として
  本ファイルでは無効化。本番化時に有効化する。
- **CloudFront の cache TTL = 0**: token 付き API レスポンスをキャッシュ
  しないため。frontend の静的アセットは Next.js の `_next/static/*` を別
  cache behavior に分けて積極キャッシュするのが本番の追加最適化。

## ローカルでの確認

```bash
cd instagram/infra/terraform
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate
```

CI (`.github/workflows/ci.yml` の `instagram-terraform` ジョブ) でも同じ
コマンドが回る。
