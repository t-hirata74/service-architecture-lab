# ADR 0004: npm workspaces monorepo + shared/ zod スキーマで FE/BE 型共有

## ステータス

Accepted（2026-06-10）

## コンテキスト

TypeScript フルスタックの最大の利点は「FE と BE が同じ型で同じプロトコルを喋れる」ことにある。本プロジェクトでは sync protocol (mutation コマンド / op payload / WS メッセージ / bootstrap・delta レスポンス) が FE/BE の契約そのものであり、これが二重定義されると optimistic 適用 (ADR 0003) と server 適用の意味がズレて収束が壊れる。

要件:

- mutation 引数・op payload・WS メッセージの**スキーマが単一定義**で、両側の入力検証にも使える
- 楽観適用の reducer (op → entity への適用) を FE/BE で**意味的に揃える**
- 既存リポの慣行 (各サービス独立 / npm / CI は npm ci) から大きく逸脱しない

本リポ初の monorepo 構成になるため、workspace ツールの選定も本 ADR で扱う。

## 決定

**npm workspaces (linear/ を root) + `shared/` workspace に zod スキーマと reducer を置く**。

- `linear/package.json` に `"workspaces": ["shared", "backend", "frontend"]`。`shared` は `@linear/shared` として両側から import
- `shared/` の内容物:
  - **entity スキーマ** (Issue / Team / WorkflowState / Label / Comment …) と TS 型 (`z.infer`)
  - **mutation コマンドスキーマ** (`createIssue` / `moveIssue` / … の discriminated union)
  - **op / WS メッセージ / bootstrap / delta のプロトコル型**
  - **reducer** — op を entity マップに適用する純関数 (FE の confirmed/pending 適用で使用。BE はテストで意味の一致を検証)
- backend は自作 **ZodValidationPipe** で mutation 入力を shared スキーマ検証 (ADR 0001)。frontend はフォーム検証と WS 受信メッセージの parse に同じスキーマを使う
- API client は thin fetch wrapper (shared の型を付けるだけ)。コード生成はしない

## 検討した選択肢

### 1. npm workspaces + shared zod package ← 採用

- 追加ツールなし (npm 標準機能)。CI も既存の `npm ci` 慣行のまま
- スキーマが**ランタイム検証と型の両方**を担い、契約が 1 ファイルに見える

### 2. tRPC

- end-to-end の型推論が最強で、実務でも人気
- 欠点: HTTP API の形が tRPC ランタイムに隠れ、「sync protocol を設計する」という学習の主役が見えなくなる。WS の op push / delta catch-up は tRPC のモデル (procedure 呼び出し) に乗らず、結局自前プロトコルが併存して二重化する

### 3. OpenAPI codegen (@nestjs/swagger → openapi-typescript)

- REST 契約の業界標準。他言語クライアントにも開ける
- 欠点: decorator から生成されるスキーマは zod ほど表現力がなく、codegen ステップと生成物の管理が増える。WS メッセージは OpenAPI の範囲外で、結局 shared 型が別途必要になる

### 4. pnpm workspaces (+ turborepo)

- 実務モノレポの最頻出。install 速度・厳密な依存解決が優れる
- 欠点: host への新規ツール導入になり、リポの他プロジェクト (npm 統一) と CI 慣行が割れる。本プロジェクトの規模 (3 workspace) では npm で困らない

## 採用理由

- **学習価値**: 「スキーマ駆動の契約共有」という TS フルスタック固有の設計を、ライブラリに隠されず素の構成で組む。reducer 共有により「楽観適用と server 適用の意味の一致」という sync engine の核心が型で表現される
- **アーキテクチャ妥当性**: zod を契約の単一源泉にする構成は実務の TS モノレポで標準的。tRPC/codegen との比較判断自体が実務でよく問われる
- **責務分離**: プロトコル定義が `shared/` に隔離され、backend のドメイン実装・frontend の UI 実装から独立に読める
- **将来の拡張性**: workspace が増えたら (e2e 共通 fixture 等) pnpm/turborepo への移行は機械的に可能

## 却下理由

- tRPC: プロトコル設計が学習対象なのに、それをランタイムに隠してしまう。WS 同期と二重化する
- OpenAPI codegen: WS をカバーできず shared 型が結局必要。生成物管理のコストだけ増える
- pnpm: リポ慣行 (npm 統一) との不整合と新規ツール導入に、3 workspace 規模の利得が見合わない

## 引き受けるトレードオフ

- **npm workspaces の素朴さ**: タスクランナーがないので `npm run -w backend test` 形式で個別実行する。Makefile (リポ慣行) で吸収
- **OpenAPI ドキュメントを持たない**: slack/youtube のような openapi-lint ジョブは作れない。契約の可読性は shared/ のスキーマ定義自体で担保する
- **reducer の二重実装リスク**: BE は DB 更新、FE は in-memory 適用で、完全に同一コードにはできない。「同じ mutation 列 → 同じ最終状態」を jest/vitest の共通 fixture で突き合わせて緩和する (Phase 3-4)

## このADRを守るテスト / 実装ポインタ

- `linear/shared/src/schema/`（予定）— entity / mutation / protocol スキーマの単一定義
- `linear/backend/src/common/zod-validation.pipe.ts`（予定）— shared スキーマでの入力検証
- `linear/shared/src/reducer.test.ts` + `linear/backend/test/reducer-parity.e2e-spec.ts`（予定）— FE reducer と BE 適用結果の一致 (parity) テスト

## 関連 ADR

- ADR 0001: ZodValidationPipe (class-validator 非採用) の根拠
- ADR 0003: shared reducer を使う optimistic 適用
