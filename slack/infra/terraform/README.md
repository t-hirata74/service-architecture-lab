# slack / infra / terraform

> **設計図用途**：このコードは `terraform apply` する想定ではない（CLAUDE.md 参照）。  
> 「本番化するなら AWS 上でどう組むか」を Terraform として読み取れる形で残すことが目的。

## 全体像

```mermaid
flowchart LR
    User((User)) --> CF[CloudFront]
    CF --> ALB[ALB<br/>HTTPS]
    subgraph "VPC 10.0.0.0/16"
      subgraph Public[Public Subnets x3 AZ]
        ALB
        NAT[NAT Gateway x3]
      end
      subgraph PrivateApp[Private App Subnets x3 AZ]
        FE[Next.js<br/>ECS Fargate]
        BE[Rails 8<br/>ECS Fargate]
        AW[ai-worker<br/>ECS Fargate]
      end
      subgraph PrivateData[Private Data Subnets x3 AZ]
        RDS[(Aurora MySQL<br/>Multi-AZ)]
        EC[(ElastiCache Redis<br/>Cluster Mode)]
      end
      ALB --> FE
      ALB --> BE
      BE --> AW
      BE --> RDS
      BE --> EC
    end
    BE --> S3[(S3<br/>添付/エクスポート)]
    BE --> SQS[SQS<br/>非同期通知]
    Logs[CloudWatch Logs]
    BE -.-> Logs
    FE -.-> Logs
    AW -.-> Logs
```

## ファイル構成

| ファイル | 内容 |
| --- | --- |
| `versions.tf` | Terraform / provider バージョン固定、backend 設定（コメントアウト） |
| `variables.tf` | 入力変数（リージョン・AZ・コンテナイメージ・ドメイン等） |
| `outputs.tf` | ALB DNS / RDS endpoint 等の出力 |
| `network.tf` | VPC + 3-AZ public/private subnets + NAT |
| `security_groups.tf` | ALB / ECS / RDS / Redis 用 SG |
| `alb.tf` | ALB + Listener + Target Groups（path 振り分け） |
| `ecs.tf` | ECS Cluster + 3 Service (frontend / backend / ai-worker) |
| `rds.tf` | Aurora MySQL クラスタ（ADR 0003）|
| `elasticache.tf` | Redis クラスタ（ADR 0001 の Pub/Sub 用）|
| `s3.tf` | 添付ファイル / エクスポート用バケット |
| `sqs.tf` | 非同期通知キュー（拡張余地） |
| `cloudfront.tf` | CDN（静的アセット + ALB オリジン） |
| `iam.tf` | ECS task / execution roles |
| `cloudwatch.tf` | Log groups + 主要アラーム |
| `secrets.tf` | DB password, JWT secret 等の Secrets Manager |

## 設計判断

[ADR 0006: 本番デプロイ先に ECS Fargate + Aurora MySQL を採用](../../docs/adr/0006-production-aws-architecture.md) を参照。

## 想定コスト感（東京リージョン）

| 区分 | 月額目安 |
| --- | --- |
| ALB | ~25 USD |
| NAT Gateway × 3 | ~150 USD（HA、削れる） |
| ECS Fargate (3 サービス × 2 task × 0.5 vCPU/1 GB) | ~120 USD |
| Aurora MySQL (db.t3.medium × 2 + Storage) | ~150 USD |
| ElastiCache Redis (cache.t3.micro × 2) | ~30 USD |
| S3 / CloudFront / SQS / CloudWatch | ~20 USD |
| **合計** | **~500 USD/月** |

「本番化するならこの規模感」を読者に伝えるための数字。実際は適用しない。

## 実行しないが確認したい場合

```bash
cd slack/infra/terraform
terraform init -backend=false
terraform validate
terraform fmt -check
```
