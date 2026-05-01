# ADR 0001: API スタイルとして GraphQL を採用

## ステータス

Accepted（2026-05-01）

## コンテキスト

`github` プロジェクトの中核技術課題は **「Issue / PR / Review / Permission の関係グラフ」** を扱うこと。
画面ごとに必要なフィールドが大きく異なり (一覧では title / author / status だけ、詳細では body / comments / reviews / checks / participants まで)、
リソース間のリンクを複数段で辿る要求が多い。

制約：

- ローカル完結（外部 SaaS 依存なし）
- リポジトリ全体で API スタイルは固定せず、プロジェクト固有の技術課題で選ぶ ([../../../docs/api-style.md](../../../docs/api-style.md))
- slack / youtube は REST + OpenAPI で揃えており、ここで **意識的に異なる API スタイルを学ぶ** 価値がある
- 実 GitHub の v4 API も GraphQL を主軸にしており、モチーフとの整合がある

## 決定

**`graphql-ruby` をバックエンド、`urql` をフロントエンドに採用する** を選ぶ。

- Schema-first：`backend/app/graphql/schema.graphql`（自動エクスポート）が単一ソース
- N+1 は `graphql-batch` (Shopify 製) で解決し、テストで保証する
- Mutation は **action 単位**で切る（`createIssue`, `assignReviewer`, `requestReview`, `mergePullRequest`）。汎用 `updateIssue` は作らない
- 認可は **resolver / field 単位**で `pundit` 相当を適用（権限グラフは ADR 0002 を参照）
- Frontend は `urql` + `@graphql-codegen` で型生成。`useQuery` / `useMutation` を直接書く方針

## 検討した選択肢

### 1. GraphQL (graphql-ruby + urql) ← 採用

- 関係グラフを 1 リクエストで投影できる
- フィールド単位の認可と相性がいい（権限グラフが学習対象）
- 実 GitHub v4 と整合

### 2. REST + OpenAPI

- slack / youtube と同じスタックで運用コスト低
- 欠点: Issue 詳細画面のような「複合ビュー」で endpoint 爆発、N+1 議論が分散
- 欠点: 既に slack / youtube で 2 回学習済み。**学習価値が薄い**

### 3. tRPC / Hotwire / RPC スタイル

- TypeScript モノレポでない以上 tRPC は採用しづらい (Rails が backend)
- Hotwire は SSR フレームワーク前提で Next.js とは噛み合わない

## 採用理由

- **学習価値**: 本リポジトリでまだ扱っていない API スタイル。N+1 / dataloader / field 認可は GraphQL 固有の論点
- **アーキテクチャ妥当性**: 関係グラフが主役のドメインで GraphQL は素直な選択。実 GitHub も同じ判断
- **責務分離**: クエリ最適化が backend に閉じ、frontend は宣言的に欲しい形を要求できる
- **将来の拡張性**: subscription を CI ステータス更新に繋げる余地（ADR 0004 で扱う）

## 却下理由

- REST + OpenAPI: 学習済みスタックで重複。関係グラフ系の課題が薄まる
- tRPC: Rails backend と整合しない
- Hotwire: Next.js を捨てる必要があり frontend スタックが重複学習にならない

## 引き受けるトレードオフ

- **キャッシュ**: HTTP / CDN レイヤーで効きにくい。urql の document cache に倒す
- **スキーマ進化**: deprecation 運用が REST より重い (フィールド削除に時間がかかる)
- **運用コスト**: GraphiQL / Apollo Studio 相当を入れない簡素運用。エラー観測は development の GraphiQL で十分とする
- **認可の複雑化**: フィールド単位認可は学習目的では狙いどおりだが、ドメインが広がるとテストが膨らむ

## このADRを守るテスト / 実装ポインタ（Phase 2 以降で実装）

- `github/backend/app/graphql/schema.graphql` — 自動エクスポートされる単一スキーマ
- `github/backend/app/graphql/types/` — Type 定義（Issue / PullRequest / Review / Repository / User）
- `github/backend/app/graphql/mutations/` — action 単位 mutation
- `github/backend/spec/graphql/n_plus_one_spec.rb` — `graphql-batch` の効果を query count で保証
- `github/frontend/src/gql/` — `@graphql-codegen` 出力の TS 型

## 関連 ADR

- ADR 0002: 権限グラフのモデリング
- ADR 0003: Issue / PR / Review データモデル
- ADR 0004（予定）: CI ステータス集約と subscription
