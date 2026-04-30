# ADR 0006: 本番デプロイ先に AWS (ECS Fargate + Aurora) を採用する

## ステータス

Accepted（2026-04-30）

## コンテキスト

CLAUDE.md は「Terraform は実行しないが設計図として用途」と定めており、本番化の妥当性を **コードとして読める形**で示す必要がある。Slack 風プロジェクトをそのままクラウドにデプロイすると仮定したとき、構成の指針を ADR として残す。

要件：

- 3-AZ 高可用構成（学習目的でも HA 設計を見せる）
- ADR 0001 (Redis Pub/Sub)、ADR 0003 (MySQL) と整合する
- Frontend (Next.js SSR)、Backend (Rails)、ai-worker (FastAPI) の 3 サービスを統一的にデプロイできる
- 学習価値が高く、実務でも採用例が多い構成

## 決定

**AWS 上に以下の構成で組む** ことを基本路線とする。実 apply はしない。

| レイヤー | 採用 |
| --- | --- |
| ネットワーク | VPC（10.0.0.0/16）、3-AZ public/private subnets、AZ ごと NAT |
| エッジ | CloudFront（静的アセットキャッシュ）→ ALB（HTTPS, path 振り分け） |
| アプリ | ECS Fargate（frontend / backend / ai-worker、各 2 task） |
| DB | Aurora MySQL Serverless v2（writer + reader、Multi-AZ）|
| キャッシュ／配信基盤 | ElastiCache Redis（replication group、Multi-AZ）|
| ストレージ | S3（添付・エクスポート） |
| メッセージング | SQS（通知ワーカー用、DLQ 付き） |
| シークレット | Secrets Manager（DB password / Rails master key） |
| 観測 | CloudWatch Logs + 主要メトリクスアラーム |

## 検討した選択肢

### コンピュート

| 案 | 評価 |
| --- | --- |
| **ECS Fargate** ← 採用 | サーバ管理不要、3 サービスを統一的に運用可能、autoscaling 容易 |
| EKS (Kubernetes) | 機能豊富だが学習・運用コストが Fargate より明確に重い。本プロジェクト規模では過剰 |
| EC2 + Auto Scaling Group | OS パッチ等の運用負担が増える。学習目的なら ECS で十分 |
| Lambda | ai-worker はコールドスタート問題、Rails はそもそも長時間プロセス前提で不向き |

### DB

| 案 | 評価 |
| --- | --- |
| **Aurora MySQL Serverless v2** ← 採用 | ADR 0003 の MySQL 採用方針に整合。serverless v2 で負荷追従、Multi-AZ で HA |
| RDS for MySQL (provisioned) | 安価で枯れているが、burst 対応や failover の自動化で Aurora に劣る |
| Aurora PostgreSQL | ADR 0003 で却下した方向に逆行 |
| DynamoDB | チャットの読み書きパターンと相性は良いが、Slack 実構成 (MySQL+Vitess) と離れすぎる |

### Pub/Sub バックエンド

| 案 | 評価 |
| --- | --- |
| **ElastiCache Redis** ← 採用 | ADR 0001 のローカル構成と本番が一致、ActionCable Redis adapter 公式サポート |
| MemoryDB for Redis | 永続化が要る場合に有力だが、Pub/Sub 用途では Redis の at-most-once で十分 |
| MSK (Kafka) | スケール余地は大きいが、ローカル構成 (Redis Pub/Sub) との乖離が大きく学習価値が下がる |

### エッジ

| 案 | 評価 |
| --- | --- |
| **CloudFront + ALB** ← 採用 | 静的アセットは CloudFront キャッシュ、SSR/REST/WebSocket は ALB 経由で透過。実務頻出構成 |
| ALB のみ | キャッシュなし、Next.js のアセット配信効率が悪い |
| API Gateway | WebSocket は別 API（HTTP API）が必要で構成が複雑化 |

## 採用理由

- **HA 設計を素直に見せられる**：3-AZ subnet + Multi-AZ DB/Redis の典型構成は教材として優秀
- **ローカル構成との対応関係が明快**：MySQL/Redis/3 サービスの責務分離をそのまま反映できる
- **Fargate で運用学習が深掘り**：Task Definition / Service Discovery / IAM Task Role の分離は実務でも頻出
- **コスト構造が読みやすい**：項目別の月額目安を README に書ける（NAT × 3 で ~150 USD など）

## 引き受けるトレードオフ

- **コスト：HA 維持で月 ~500 USD クラス**：NAT × 3、Aurora、CloudFront 等が積み上がる。コスト重視なら NAT 単一化、reader 削減で半額以下にできる
- **WebSocket × CloudFront の制約**：Sticky session を ALB target group に持たせる（WebSocket 接続維持のため）。CloudFront は WebSocket をサポートするが、特定の cache policy を使うと壊れるので default = caching-disabled
- **Aurora Serverless v2 の最低キャパシティ**：常時 0.5 ACU 以上で課金される。完全停止は不可
- **frontend を ECS で動かす**：S3 + CloudFront だけにできれば安いが、Next.js SSR/middleware を素直に動かすため Fargate を選択
- **ai-worker は ECS で常駐**：将来 Bedrock 等の本番 AI 呼び出しに切り替えるなら Lambda の方が適することもある（ADR を別途起こす想定）

## 関連 ADR

- ADR 0001: リアルタイム配信方式 → ElastiCache Redis 採用根拠
- ADR 0003: DB に MySQL → Aurora MySQL に直結
- ADR 0004: 認証方式 → JWT が ALB / CloudFront 透過で動くことを前提

## 参考

- AWS Well-Architected Framework
- ECS Fargate vs EKS の選定指針（AWS 公式）
- Aurora Serverless v2 の課金単位 (ACU)
