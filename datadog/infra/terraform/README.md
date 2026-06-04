# Datadog — Terraform 設計図 (本番想定)

CLAUDE.md の方針通り **`terraform apply` はしない**。本番化するならどう設計するかを示す
ドキュメントとして `terraform fmt` / `terraform validate` を CI で通すのが目的。

## 構成

| ファイル | 役割 |
| --- | --- |
| `versions.tf` | provider バージョン固定 + tag 設定 |
| `variables.tf` | region / VPC / domain / instance class / H3 解像度 |
| `network.tf` | VPC / 3-AZ public / private (app / data) subnet / NAT |
| `security_groups.tf` | ALB / frontend / backend / ai-worker / RDS の SG |
| `alb.tf` | HTTPS listener + path-based routing (`/ws` `/auth/*` `/me` `/trips*` `/demand` `/healthz` を backend、その他 frontend) |
| `ecs.tf` | Fargate cluster + 3 service (frontend / backend / ai-worker) + Service Discovery |
| `rds.tf` | MySQL single writer (multi-AZ、deletion protection on) |
| `iam.tf` | execution role + 各 task role |
| `cloudwatch.tf` | ECS log group |
| `secrets.tf` | Secrets Manager (DATABASE_URL / JWT_SECRET / AI_INTERNAL_TOKEN) |
| `outputs.tf` | ALB / RDS / Service Discovery endpoint |

## 設計上の注記 (discord / perplexity との差分)

- **Redis 不採用** (ADR 0003: matcher は in-memory channel) — perplexity の rate limit store、instagram の Celery broker に相当する Redis レイヤを置かない。idle-driver registry と offer channel はプロセス内に閉じる。
- **ai-worker は MySQL を読まない** (ADR 0004) — ETA / demand の入力 (座標 / H3 cell) は Go dispatch が body で渡す。よって Aurora reader endpoint も不要、標準 MySQL に絞った。ai-worker は stateless なので `desired_count = 2` で水平分散できる (backend と対照的)。
- **backend は `desired_count = 1` が原則** — discord の per-guild Hub より制約が強い。matcher の idle-driver registry と driver の WS 接続が同一プロセスに閉じるうえ、**rider(REST) と driver(WS) が別経路で同じ matcher に出会う**必要があるため、タスクを分散すると「別タスクの driver」へ offer できない。REST 負荷分散だけが欲しい場合や本格的な水平スケールは、派生 ADR (cell→task の consistent hashing or 共有メッセージバス) を実装してから ECS 配置を見直す。
- **ALB の `idle_timeout = 4000`** — driver の WebSocket を idle で殺さないため。gorilla の ping/pong (60s, `internal/ws/conn.go`) があるので 4000s で十分余裕。
- **`/ws` への sticky session は OFF** — どのみち単一 backend タスク前提なので不要。cell→task 固定が要るスケール段階になったら派生 ADR で consistent hashing を入れる。
- **Secrets ローテーション** — `JWT_SECRET` を入れ替えると REST / driver WS 双方の token が無効化される。本ファイルでは 1 値固定、ローテーション戦略は派生 ADR で扱う。

## ローカルでの確認

```bash
cd datadog/infra/terraform
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate
```

CI (`.github/workflows/ci.yml` の `datadog-terraform` ジョブ) でも同じコマンドが回る。
