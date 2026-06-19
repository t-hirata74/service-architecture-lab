# ADR 0004: backend = Hono + Drizzle、FE/BE 型共有 = Hono RPC — linear (NestJS/Prisma/zod) との対比

## ステータス

Accepted（2026-06-19）

## コンテキスト

本リポ 2 本目の TypeScript フルスタック。1 本目の linear は ADR 0001 で **NestJS + Prisma + 共有 zod** を採用し、その際 **Hono を「実務採用例が薄く時期尚早」、Drizzle を「SQL 寄りの学びは Go 側で獲得済み」として却下**した（linear ADR 0001 却下理由）。

freee はその却下した組を**意図的に拾い**、TS フルスタックの「もう一方の流派」を学ぶ。本リポが大切にする「同ドメインを別軸で実装して対比する」（slack↔discord、instagram↔reddit）と同じ構図を、TS backend 内（NestJS↔Hono）で作る。

選定の前提：

- freee の主役は **Postgres RLS + 複式簿記の不変条件**（ADR 0001-0003）であり、sync engine のような重い常駐ロジックや WS は無い。**リクエストスコープの DB 文脈注入（`SET LOCAL`）** が backend の肝。
- frontend は本リポ初の **React + Vite (SPA)**（Next.js ではない）。SSR / App Router は不要で、純 CSR + 型付き API クライアントで足りる。
- FE/BE 型共有は本リポで 3 つ目の流派になる（github=graphql-codegen、linear=共有 zod、freee=Hono RPC）。

## 決定

**backend = Hono、ORM = Drizzle、FE/BE 型共有 = Hono RPC (`hc<AppType>`)、frontend = React + Vite、npm workspaces monorepo（`backend` / `frontend` / `shared`）** を採用する。

- **Hono**: ミドルウェア中心の薄い構成。ADR 0001 の tenant middleware（トランザクション + `SET LOCAL app.current_company`）が Hono の `createMiddleware` に素直に乗る
- **Drizzle**: `db.transaction(async (tx) => { await tx.execute(sql\`SET LOCAL app.current_company = ...\`); ... })` で **RLS の文脈注入とクエリを同一トランザクションに閉じる**のが SQL-first な Drizzle だと透明。生 SQL（`EXCLUDE` 制約 / constraint trigger / `SET LOCAL`）を migration にそのまま書ける
- **Hono RPC**: backend のルート定義から `AppType` を export し、frontend は `hc<AppType>(baseURL)` で **codegen 無しにエンドツーエンド型**を得る。入力検証は `@hono/zod-validator` + zod で行い、その zod スキーマは `shared` に置いて RPC 型と検証を一致させる
- **NUMERIC 境界**: 金額（ADR 0002 の `NUMERIC`）は JS `number` を使わず文字列で運ぶ。`shared` の zod スキーマで金額型を一元定義し、RPC の入出力境界で検証する

## 検討した選択肢

### backend フレームワーク

| | Hono ← 採用 | NestJS (linear) | Fastify 素組み |
| --- | --- | --- | --- |
| 構成 | 薄い・ミドルウェア中心 | DI / module / decorator（重い） | 自前で構築 |
| RPC 型共有 | **`hc` で codegen 不要** | 別途 codegen / 共有 zod | 自前 |
| 本 PJ 適合 | request スコープ DB 文脈注入に最適 | sync engine / WS 統合に最適 | 中立 |
| 学習対比 | **NestJS との対極を取れる** | （既習） | 足場作りに時間が偏る |

### ORM

- **Drizzle（採用）**: SQL-first。RLS / `EXCLUDE` / constraint trigger / `SET LOCAL` という **Postgres 生 SQL を多用する本 PJ** と相性が良い。linear が Prisma で経験した「`FOR UPDATE` は `$queryRaw` に逃がす」ような抽象の壁が薄い
- **Prisma（linear で既習）**: schema 単一定義は強力だが、RLS の `SET LOCAL` をトランザクションに差すのに `$executeRaw` 併用が増え、Drizzle ほど透明でない
- **生 SQL (pg)**: 最も透明だが型安全を自前で担保する手間。SQL 直書きの学びは Go 3 本で獲得済み

### 型共有

- **Hono RPC（採用）**: codegen ステップが消え、ルート定義が型の単一の真実になる。Hono 固有の体験
- 共有 zod（linear で既習）: monorepo で zod を共有。RPC と併用し検証側に使う

## 採用理由

- **学習価値**: TS フルスタックの「軽量・Web 標準・RPC」流派を、linear の「フルフレームワーク・DI・codegen/zod」流派と対比して体得。Drizzle で Postgres 生 SQL を素直に書ける
- **アーキテクチャ妥当性**: Hono + Drizzle は 2026 時点の TS エコシステムで急速に標準化しつつある軽量構成。edge / serverless 適性も実プロダクト水準
- **責務分離**: tenant 文脈注入を middleware に閉じ、ドメインハンドラは「文脈設定済み」を前提にできる（ADR 0001）
- **将来の拡張性**: SSE/WS が必要になれば Hono の `streamSSE` 等で足せる。Node ランタイム前提だが Web 標準 API ベースなので移植余地が広い

## 却下理由

- NestJS: 既習であり、本 PJ には DI / module の重さが過剰（主役は RLS と不変条件で、足場の学びは linear で済んだ）
- Fastify 素組み: 足場の自作に時間が偏る
- Prisma: RLS の `SET LOCAL` 注入が Drizzle ほど透明でない。Postgres 生 SQL 多用の本 PJ では SQL-first が勝る
- 生 SQL のみ: 型安全を自前担保するコスト。SQL の学びは Go で獲得済み

## 引き受けるトレードオフ

- **Hono RPC の型負荷**: ルートが増えると `AppType` の型推論が重くなりがち。ルートを機能単位に分割し、巨大 union を避ける
- **NUMERIC ⇄ JS の境界**: 金額を文字列で運ぶ規約を `shared` zod で固定。number 化の油断を型で塞ぐ
- **Drizzle の migration 成熟度**: Prisma Migrate ほど高機能でない。`drizzle-kit` + 生 SQL migration（RLS/trigger/EXCLUDE）併用で運用する
- **エコシステムの薄さ**: NestJS ほど周辺（guard / interceptor 等）が揃っていない。必要なものは middleware で素朴に組む

## このADRを守るテスト / 実装ポインタ

- `shared/src/index.ts` — 金額 (money 文字列) / 勘定科目 / 仕訳 / 期間の zod を FE/BE 共有 + `moneyToCents`
- `backend/src/app.ts` — `AppType` の export 起点 + SQLSTATE→HTTP マッピング (cause チェーンを辿る `pgErrorCode`)
- `frontend/src/api.ts` — `hc<AppType>` クライアント (codegen なし)
- `backend/src/middleware/tenant.ts` — Drizzle transaction + `set_config`（ADR 0001 の実体）

## 関連 ADR

- ADR 0001: RLS（`SET LOCAL` を Drizzle transaction で発行する実装根拠）
- ADR 0002: NUMERIC 金額の境界変換
- linear ADR 0001 / 0004: NestJS+Prisma / 共有 zod（本 ADR の対比対象、Hono/Drizzle を却下していた）
