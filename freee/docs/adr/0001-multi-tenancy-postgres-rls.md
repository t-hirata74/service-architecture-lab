# ADR 0001: マルチテナント分離 — shared-schema + Postgres Row-Level Security (RLS)

## ステータス

Accepted（2026-06-19）

## コンテキスト

freee / マネーフォワードは多数の事業者（= Company）を 1 プラットフォームに収容する典型的なマルチテナント SaaS。本プロジェクトでも「複数 Company が同一 backend / 同一 DB を共有しつつ、互いの会計データを参照できない」前提を再現する。

会計ドメイン特有の制約：

- **テナント越境漏洩のコストが極端に高い**。他社の仕訳・残高が見えるのは EC の商品一覧が見える以上に致命的で、「アプリ層で `WHERE company_id = ?` を書き忘れた」一箇所が即事故になる。
- 本リポは既に shopify で **MySQL のアプリ層 `shop_id` scoping**（明示 scope + concern + lint）を実装済み（shopify ADR 0002）。freee では **同じマルチテナントを「DB が強制する」側**で実装し、両者の対比を学習対象にしたい。
- 本リポ初の **Postgres** 採用。MySQL に無い RLS（Row-Level Security）を正面から使うこと自体が学習テーマ。
- ローカル完結方針のため Company は seed で 2〜3 件（例: `acme / globex`）。schema 分離・DB 分離はインフラコストの議論にすり替わるので採らない。
- 漏洩しないことを **「アプリ層の scope を意図的に外しても他社データが 0 行」** という形で spec の不変条件に固定する（アプリ層 scoping では到達できないテスト）。

## 決定

**単一 DB / shared-schema + 全 tenant-aware テーブルに `company_id` + Postgres RLS ポリシー + アプリは非特権ロールで接続し `SET LOCAL app.current_company` をトランザクションに注入** を採用する。

- すべての tenant-scoped table に `company_id BIGINT NOT NULL` + `(company_id, ...)` 複合 index を必須化
- 各テーブルで `ENABLE ROW LEVEL SECURITY` + `CREATE POLICY ... USING (company_id = current_setting('app.current_company')::bigint)`（`USING` で SELECT/UPDATE/DELETE、`WITH CHECK` で INSERT/UPDATE の越境書き込みも封じる）
- アプリの DB 接続ロールは **`NOSUPERUSER` かつ RLS をバイパスしない**（superuser / `BYPASSRLS` / テーブル所有者は RLS が効かないため、マイグレーション用ロールと実行時ロールを分ける）
- Hono の **tenant middleware** がリクエストごとにトランザクションを開き、その中で `SET LOCAL app.current_company = $1` を実行 → 同一トランザクション内のクエリだけにテナント文脈を閉じ込める（`SET LOCAL` はトランザクション終了で自動リセットされ、コネクションプール越しの混線を防ぐ）
- Drizzle はこのトランザクション（`db.transaction(...)`）を介してのみクエリを発行する（ADR 0004）

## 検討した選択肢

### 1. shared-schema + RLS ← 採用

- 利点: テナント分離を **DB が最終防衛線として強制**。アプリ層の scope 書き忘れがあっても他社行に到達できない
- 利点: 単一 migration / cross-tenant 集計（運用 admin 用）は `BYPASSRLS` ロールで SQL 1 本
- 利点: Postgres 固有機能の学習。shopify のアプリ層 scoping との「DB 強制 vs アプリ層」対比が成立

### 2. アプリ層 scoping のみ（shopify ADR 0002 と同型）

- 利点: DB 機能に依存せず移植性が高い。実装が単純
- 欠点: **最後の防衛線が無い**。本リポは shopify で既に経験済みなので、freee で同じ型をなぞる学習価値が薄い

### 3. schema-per-tenant（`SET search_path`）

- 利点: 物理分離に近く漏洩リスクが低い
- 欠点: migration を全 schema に流す運用コスト。テナント数が動的に増える設計が重く、RLS という主題から逸れる

### 4. database-per-tenant

- 利点: 完全分離
- 欠点: ローカル学習には過剰。接続プール管理の複雑さだけが残る

## 採用理由

- **学習価値**: RLS の運用論点（ポリシー設計 / 非特権ロール / `SET LOCAL` とプール / `BYPASSRLS` 例外）を最小コストで全部触れる。会計という「漏洩が致命的」なドメインが RLS の動機を本質的にする
- **アーキテクチャ妥当性**: Postgres RLS は Supabase / 多くの B2B SaaS が採る実プロダクトの定番。「DB で締める」設計を示せる
- **責務分離**: tenant 解決は middleware が一手に引き受け、ドメインロジックは `app.current_company` が設定済みであることを当然の前提にできる
- **将来の拡張性**: ホットな company だけ別 DB に分離する垂直分割の余地を `company_id` を partition key に残して確保

## 却下理由

- アプリ層のみ: 防衛線が 1 枚で、shopify と学習が重複する
- schema/DB-per-tenant: ローカル完結の本リポでは運用コストの議論に逸れる

## 引き受けるトレードオフ

- **`SET LOCAL` 規律**: 全クエリがトランザクション内である必要がある。トランザクション外クエリはテナント文脈なしで RLS により 0 行になる（fail-closed なので安全側に倒れる）。middleware で必ずトランザクションを張る規約を spec で固定する
- **接続ロールの分離**: マイグレーション（テーブル所有者 = RLS バイパス）と実行時（非特権 = RLS 適用）でロールを分ける運用が増える。`docker-entrypoint-initdb.d` か migration でアプリロールを作る
- **RLS の性能**: ポリシーの `USING` 条件が全クエリに AND される。`(company_id, ...)` 複合 index で吸収する。MVP では計測まではしない
- **cross-tenant 集計**: 運用 admin の全社横断クエリは `BYPASSRLS` を持つ別ロール経由に限定し、アプリの実行時ロールには漏らさない

## このADRを守るテスト / 実装ポインタ（実装後に埋める）

- `backend/test/multi_tenancy/rls_isolation.test.ts`（予定）— Company A の文脈で **アプリ層 scope を外しても** Company B の仕訳が 0 行になること（アプリ層 scoping では書けない、RLS 固有の不変条件テスト）
- `backend/src/middleware/tenant.ts`（予定）— トランザクション + `SET LOCAL app.current_company`
- `backend/drizzle/`（予定）— 全 tenant-scoped table の `ENABLE ROW LEVEL SECURITY` + ポリシー + アプリ用 `NOSUPERUSER` ロール作成

## 関連 ADR

- ADR 0002: 複式簿記 invariant（仕訳テーブルも `company_id` を持ち RLS 対象）
- ADR 0003: 期末締め（accounting_periods も company スコープ）
- ADR 0004: Drizzle / Hono RPC（`SET LOCAL` を Drizzle transaction でどう発行するか）
- shopify ADR 0002: アプリ層 `shop_id` scoping（本 ADR の対比対象）
