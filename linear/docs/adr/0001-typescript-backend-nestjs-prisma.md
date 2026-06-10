# ADR 0001: TypeScript backend に NestJS (Express platform) + Prisma を採用する

## ステータス

Accepted（2026-06-10）

## コンテキスト

本リポ初の TypeScript backend プロジェクト。これまで Rails 8 本 / Django 1 / FastAPI 1 / Go 3 で「その言語が選ばれる典型ドメイン」を学んできた (README 言語別バックエンド方針)。TS backend では以下を学習対象にしたい:

- **TS 実務構成の検証** — Rails で実務構成を検証してきたのと対になる、「Node 版の実務標準」での層分け・DI・テスト構成
- **FE/BE 型共有** — TypeScript フルスタックでしか成立しない、スキーマ単一定義の開発体験 (ADR 0004)
- **sync engine** (ADR 0002/0003) を支える、トランザクション境界が明示的な ORM

ユーザーは初の TS フルスタックであり、最小構成ではなく**学習面積を広く取る**方針 (ボリューム重視)。フレームワーク選定はユーザー確認済み (NestJS)。本 ADR は採用理由の記録と、platform / ORM / module 構成の決定を扱う。

## 決定

**NestJS (Express platform) + Prisma + zod validation pipe** を採用し、module を責務単位に分割する。

- HTTP platform は default の **Express adapter**。WS gateway は `@nestjs/platform-ws` (ADR 0005)
- ORM は **Prisma** — schema 単一定義 + migrate + 生成型。採番 + log append の原子性は `prisma.$transaction` (interactive transaction) で担保
- validation は Nest 標準の class-validator ではなく **zod + 自作 ZodValidationPipe** — `shared/` のスキーマを BE 入力検証に直結させるため (ADR 0004)
- module 構成: `auth / workspaces / teams / issues / mutations / sync / realtime / ai / prisma(global)`。書き込み入口は `mutations` に一本化 (architecture.md)
- テストは **jest (Nest 標準) + supertest** (e2e)。並行性の不変条件テストは ADR 0002 参照

## 検討した選択肢

### 1. NestJS (Express platform) + Prisma ← 採用

- DI / module / decorator による層分け規約が **Rails の「設計済みの構造」に最も近く**、国内実務の TS backend で採用最多。Rails 実務構成検証との対比が成立する
- `Test.createTestingModule` による DI 差し替えテスト、`@nestjs/websockets` の WS 統合など、本プロジェクトの構成要素が一級でサポートされる

### 2. Fastify + zod の素組み

- 軽量・高速。アプリ構造を自分で設計するため学習濃度は高い
- 欠点: DI / レイヤ規約 / テスト基盤をすべて自前にすると、学習の主役 (sync engine) より足場作りに時間が偏る。「実務標準構成の検証」という目的にも合わない

### 3. Hono

- Web 標準ベースでモダン、RPC モードの型共有は魅力
- 欠点: 常駐サーバ + WS + DI の実務採用例がまだ薄く、「TS 実務構成」の検証材料として弱い

### ORM: Prisma ← 採用 / TypeORM / Drizzle

- **Prisma**: schema.prisma が単一の真実で migrate と型生成が一体。interactive transaction で「counter FOR UPDATE → ops INSERT → COMMIT」を素直に書ける。国内実務シェアも最大
- **TypeORM**: Nest ドキュメントの標準だが、decorator entity の型安全が弱く、lazy relation 等の暗黙挙動が学習ノイズになる
- **Drizzle**: SQL-first で軽く魅力的だが、migrate 周りの成熟度と実務シェアで Prisma に譲る。生 SQL に近い学びは Go 3 プロジェクト (database/sql) で獲得済み

## 採用理由

- **学習価値**: 「Node 版 Rails」としての NestJS の構造 (module / provider / guard / pipe / interceptor) を、guard=認可・pipe=zod 検証・gateway=WS と全部使う題材になっている
- **アーキテクチャ妥当性**: NestJS + Prisma は 2026 時点の国内 TS backend の最頻出構成。ポートフォリオとして「実務でそのまま通じる構成」を示せる
- **責務分離**: 書き込み入口を `mutations` module に一本化し、ドメイン module → `realtime` への依存を持たせない規律が module 境界で表現できる
- **将来の拡張性**: Express → Fastify adapter 切替、Prisma → 生 SQL 併用 (`$queryRaw`) など、性能側への発展余地を残す

## 却下理由

- Fastify 素組み: 足場の自作に学習時間が偏り、sync engine という主題から逸れる
- Hono: 実務構成の検証材料として時期尚早
- TypeORM: 型安全の弱さと暗黙挙動が、初 TS プロジェクトの学習ノイズになる
- Drizzle: SQL 寄りの学びは Go 側で獲得済み。TS 側は「実務最頻出」を優先

## 引き受けるトレードオフ

- **NestJS の重さ**: decorator / DI のボイラープレートが増える。「実務標準の検証」という目的のコストとして許容
- **Prisma の抽象**: `FOR UPDATE` は `$queryRaw` で書く必要がある (Prisma API に row lock がない)。採番部分だけ生 SQL が混ざることを ADR 0002 で明示する
- **class-validator 非採用**: Nest 公式サンプルから外れる。zod pipe の自作 (数十行) と引き換えに FE/BE スキーマ単一化を取る (ADR 0004)

## このADRを守るテスト / 実装ポインタ

- `linear/backend/src/`（予定）— module 構成が本 ADR の表と一致すること
- `linear/backend/test/`（予定）— supertest e2e が `POST /mutations` 経由でのみ書き込みできることを検証
- ESLint boundary ルール（予定・Phase 2 で検討）— ドメイン module から `realtime` への import 禁止

## 関連 ADR

- ADR 0002: sync log の採番設計 (Prisma interactive transaction + `$queryRaw FOR UPDATE`)
- ADR 0004: zod スキーマ共有 (ZodValidationPipe の根拠)
- ADR 0005: realtime 配信 (`@nestjs/platform-ws` の選定)
