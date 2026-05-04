# Discord — Terraform 設計図 (本番想定)

CLAUDE.md の方針通り **`terraform apply` はしない**。本番化するならどう設計するかを示す
ドキュメントとして `terraform fmt` / `terraform validate` を CI で通すのが目的。

## 構成

| ファイル | 役割 |
| --- | --- |
| `versions.tf` | provider バージョン固定 + tag 設定 |
| `variables.tf` | region / VPC / domain / instance class / heartbeat 間隔 |
| `network.tf` | VPC / 3-AZ public / private (app / data) subnet / NAT |
| `security_groups.tf` | ALB / frontend / backend / ai-worker / RDS の SG |
| `alb.tf` | HTTPS listener + path-based routing (`/gateway` `/auth/*` `/me` `/guilds*` `/channels*` `/health` を backend、その他 frontend) |
| `ecs.tf` | Fargate cluster + 3 service (frontend / backend / ai-worker) + Service Discovery |
| `rds.tf` | MySQL single writer (multi-AZ、deletion protection on) |
| `iam.tf` | execution role + 各 task role |
| `cloudwatch.tf` | ECS log group |
| `secrets.tf` | Secrets Manager (DATABASE_URL / JWT_SECRET / AI_INTERNAL_TOKEN) |
| `outputs.tf` | ALB / RDS / Service Discovery endpoint |

## 設計上の注記 (instagram / perplexity との差分)

- **Redis 不採用** (ADR 0001 単一プロセス Hub) — instagram の Celery broker、perplexity の rate limit store に相当する Redis レイヤを置かない。Hub の `clients` map と `presences` map はインスタンス内 in-memory のみ。
- **ai-worker は MySQL を読まない** — メッセージ snippets は Go gateway が body で渡す。よって Aurora reader endpoint も不要、標準 MySQL に絞った。
- **WebSocket スケールアウトは未解決** — `desired_count = 2` で立ててはいるが、ADR 0001 通り **同 guild の subscriber が別タスクに分散すると fan-out できない**。REST 負荷分散だけが効く構成。本格的に水平スケールしたい場合は派生 ADR 0005 (multi-process + Redis pub/sub) を実装してから ECS shard 配置を見直す。
- **ALB の `idle_timeout = 4000`** — WebSocket を idle で殺さないため。app 層 HEARTBEAT は 41250ms (ADR 0003) なので 4000s なら十分余裕。
- **`/gateway` への sticky session は OFF** — sticky cookie でも「最初に upgrade したインスタンスに固定する」だけで、同 guild ハッシュにはならない。中途半端に効かせるよりは reconnect 時に新インスタンスを引いて再 IDENTIFY する方が一貫している。
- **Secrets ローテーション** — `JWT_SECRET` を入れ替えると全 client が再ログインを強要される。本ファイルでは 1 値固定、ローテーション戦略は派生 ADR で扱う。

## ローカルでの確認

```bash
cd discord/infra/terraform
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate
```

CI (`.github/workflows/ci.yml` の `discord-terraform` ジョブ) でも同じコマンドが回る。
