# API スタイル方針 (REST / GraphQL の選定)

各プロジェクトの **主要技術課題** に応じて REST / GraphQL を選ぶ。
リポジトリ全体で 1 つのスタイルに固定せず、**判断軸とトレードオフを学習成果として残す**。

---

## 判断軸

| 観点 | REST が向く | GraphQL が向く |
| --- | --- | --- |
| データ構造 | リソースが独立し、固定形のレスポンスで足りる | リソースの**関係グラフ**を辿り、画面ごとに必要な field が違う |
| 主要操作 | CRUD + state transition (action) | 任意のサブセット投影 / nested 取得 |
| キャッシュ | HTTP / CDN レイヤーで効かせやすい | クエリ単位の永続化キャッシュで自前管理 |
| 認可 | エンドポイント単位でリソース ABAC | フィールド単位の認可が必要（複雑化） |
| 学習コスト | 低い (Rails 標準 / OpenAPI) | 高い (graphql-ruby + dataloader + N+1 + auth) |
| 向いている技術課題 | 状態機械 / アップロード / 通知配信 / 既読同期 | 権限グラフ / Issue リレーション / 連結クエリ |

> 共通: **リアルタイム配信は WebSocket / SSE が主役**で、REST と GraphQL のどちらを選んでも直交する。

---

## プロジェクト別の選定

| プロジェクト | スタイル | 採用理由 |
| --- | --- | --- |
| `slack`   | **REST + OpenAPI** | 主要技術課題（fan-out / 既読 cursor）は WebSocket と直交。残りの CRUD は固定形で OpenAPI と相性が良い |
| `youtube` | **REST + OpenAPI** | アップロード状態機械は action ベースの REST が素直。Recommendation / 検索 / コメントも独立リソースで GraphQL に倒す価値が薄い |
| `github` (予定) | **GraphQL** | 主要技術課題が「**Issue / PR / Review / Permission の関係グラフ**」。REST だと endpoint 爆発 + N+1 議論が分散する。実 GitHub も v4 が GraphQL |

### 選定をしない・先送りでよいケース

- **`discord` / `figma` / `zoom`**: WebRTC / CRDT が主役で、REST/GraphQL の比重が小さい。プロジェクト着手時に再検討
- **`stripe` / `shopify`**: 実プロダクトが REST 寄り。学習価値は REST 側で取りに行く
- **AI 系（chatgpt / coding-agent）**: HTTP 部分は薄い。SSE / Streaming が主役

---

## REST + OpenAPI の運用

### 採用ツール

- **`committee-rails`** — Rails の request spec で **レスポンスを OpenAPI スキーマに照合**する。スキーマと実装が乖離した瞬間にテストが落ちる
- **`openapi-typescript`** — Frontend が `openapi.yml` から TS 型を **自動生成**。`lib/api.ts` で手書きしていた型は廃止
- **`openapi-fetch`** — 上記の型を使った薄い `fetch` ラッパ（任意）

### 配置

```text
<service>/backend/docs/openapi.yml      # 単一スキーマファイル (手書き)
<service>/frontend/src/lib/api-types.ts # openapi-typescript で自動生成
```

### 規約

- **エンドポイントを実装する前に openapi.yml を書く**（schema-first）
- **request spec が openapi.yml を必ず通す**（`assert_response_schema_confirm` 等）
- **frontend は `npm run gen:api` で型再生成**。`tsc --noEmit` で乖離を検知
- **レスポンスは objects ではなく `{ items: [...] }` ラップ**を基本（ページネーション拡張余地）

### ステータスコードの規約

- `200` 成功 / `201` create / `202` async accepted
- `400` クライアントの形不正 (parameter missing 等)
- `404` リソース不在 / **状態的に隠したい（viewable でない）** 場合も 404
- `409` state conflict（例: `publish!` を非 ready から呼ぶ）
- `422` validation error（`{ errors: ["..."] }`）
- 外部依存失敗時は **`200` + `degraded: true`**（[graceful degradation](operating-patterns.md#graceful-degradation)）

---

## GraphQL の運用（github 着手時に確定）

予定だが ADR を切る前にここに先出ししておく:

- スキーマファイルを単一ソース（`<service>/backend/app/graphql/schema.graphql`）に
- `graphql-ruby` + GraphiQL（development のみ）
- N+1 は `graphql-batch` / `dataloader` で必ず潰す（テストで保証）
- Mutation は **action 単位**で切る（`createIssue`, `assignReviewer` など）。CRUD の汎用 mutator は作らない
- 認可は `pundit` 相当を **resolver / field 単位**で適用
- Frontend クライアントは `urql` か `@apollo/client` のどちらか（github 着手時の ADR で決定）

---

## 現時点の宿題

- `slack/backend` と `youtube/backend` に `committee-rails` を導入し、既存エンドポイントを `openapi.yml` に書き出す
- `slack/frontend` と `youtube/frontend` で `openapi-typescript` から型生成し、手書き型を撤去
- ADR は **プロジェクト単位で 1 本** （youtube は ADR 0007 として「REST + OpenAPI 採用」、github は着手時に「GraphQL 採用」を起こす）

---

## 関連ドキュメント

- [coding-rules/rails.md](coding-rules/rails.md) — Service オブジェクトと ai-worker 境界の共通方針
- [testing-strategy.md](testing-strategy.md) — request spec から OpenAPI を検証
- [operating-patterns.md](operating-patterns.md) — graceful degradation とエラーハンドリング規約
