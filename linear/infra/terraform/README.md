# linear — Terraform 設計図 (本番想定)

CLAUDE.md の方針通り **`terraform apply` はしない**。本番化するならどう設計するかを示す
ドキュメントとして `terraform fmt` / `terraform validate` を CI で通すのが目的。

## 構成

| ファイル | 役割 |
| --- | --- |
| `versions.tf` | provider バージョン固定 + tag 設定 |
| `variables.tf` | region / VPC / domain / instance class |
| `network.tf` | VPC / 3-AZ public / private (app / data) subnet / NAT |
| `security_groups.tf` | ALB / frontend / backend / ai-worker / RDS の SG |
| `alb.tf` | HTTPS listener + path-based routing (`/auth/*` `/mutations` `/sync/*` `/ai/*` `/workspaces` `/health` を backend、その他 frontend) |
| `ecs.tf` | Fargate cluster + 3 service (frontend / backend / ai-worker) + Service Discovery |
| `rds.tf` | MySQL single writer (multi-AZ、deletion protection on) |
| `iam.tf` | execution role + 各 task role |
| `cloudwatch.tf` | ECS log group |
| `secrets.tf` | Secrets Manager (DATABASE_URL / JWT_SECRET / AI_INTERNAL_TOKEN) |
| `outputs.tf` | ALB / RDS / Service Discovery endpoint |

## 設計上の注記 (sync engine 固有)

- **backend は `desired_count = 1` が原則** — WS room (ADR 0005) が in-memory Map のため、
  複数タスクに分散すると別タスクの WS 接続へ op push が届かない。重要なのは、それでも
  **正しさは壊れない**こと: push は at-most-once のヒントで、真実は sync log (ADR 0002)。
  client は seq の gap を検出して delta で自己修復する。失われるのはリアルタイム性のみ。
  リアルタイム性を保った水平化は Redis pub/sub 中継の派生 ADR を実装してから。
- **採番はスケールしても壊れない** — `lastSyncId` は DB の counter 行 `FOR UPDATE` で
  採番される (ADR 0002) ため、multi-task でも commit 順 = seq 順は保たれる。
  単一プロセス前提なのは「配信」だけで「順序」は DB が守る、という分離が設計の要。
- **ALB `idle_timeout = 4000`** — `/sync/ws` を idle で殺さないため。server 側に
  30s ping/pong heartbeat (RealtimeService) があるので十分余裕。
- **Redis 不採用** — キューも cache も持たない。offline 耐性は client 側
  (IndexedDB + pending queue / ADR 0003) が担う、というのが local-first 設計の特徴。
- **ai-worker は MySQL を読まない** — backend が title/candidates を body で渡す同期 REST。
  stateless なので `desired_count = 2` で水平分散できる (backend と対照的)。
