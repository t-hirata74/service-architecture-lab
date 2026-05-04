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
| `github` | **GraphQL** (graphql-ruby + urql) | 主要技術課題が「**Issue / PR / Review / Permission の関係グラフ**」。REST だと endpoint 爆発 + N+1 議論が分散する。実 GitHub も v4 が GraphQL |
| `perplexity` | **REST + SSE** (`ActionController::Live`) | 同期 API は固定形で十分、stream 部分のみ SSE で切り出す |
| `instagram` | **REST** (DRF) | フォロー / タイムラインは action ベースの REST で十分。スキーマ定義は DRF Serializer ベース |
| `discord` | **REST + WebSocket** (`/gateway`) | gateway protocol が主役、REST は補助 |
| `reddit` | **REST + JSON** (FastAPI) | サブレディット / post / comment / vote は典型的な CRUD + custom action。FastAPI 型駆動で OpenAPI 自動生成。GraphQL を入れる動機が薄い (関係グラフは comment tree だけで、それは path 列で十分扱える) |

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

## GraphQL の運用（github プロジェクトで確立）

github プロジェクト (ADR 0001) で実運用に入った構成。次に GraphQL を選ぶプロジェクトはここから始める。

### 採用ツール

- **`graphql-ruby` ~> 2.4** — schema-first ではなく **コード定義を SDL にダンプ** (rake task で `<service>/backend/docs/schema.graphql` に書き出し)
- **`GraphQL::Dataloader`** — N+1 対策。`graphql-batch` も併用可だが、新規プロジェクトは Dataloader を推奨
- **`pundit`** — 認可は **policy verb 単位**で書き、mutation / field resolver から `Pundit.policy(user, record).<verb>?` で呼ぶ
- **`urql` (frontend)** — `@graphql-codegen/cli` + `typescript-urql` で型付き hooks 生成（`gen:api` script）

### 配置

```text
<service>/backend/app/graphql/
  <service>_schema.rb                      # query / mutation / dataloader 設定
  types/                                   # *_type.rb / *_enum.rb
  mutations/base_mutation.rb               # current_user! / authorize! ヘルパ
  mutations/<action>.rb                    # createIssue, mergePullRequest など action 単位
  sources/                                 # GraphQL::Dataloader::Source 派生クラス
<service>/backend/lib/tasks/graphql.rake   # rake graphql:dump_schema
<service>/backend/docs/schema.graphql      # 自動エクスポート (CI で diff チェック)
<service>/frontend/codegen.ts              # graphql-codegen 設定
<service>/frontend/lib/gql/types.ts        # 自動生成 (commit してCI で diff チェック)
```

### 規約

- **Mutation は action 単位**: `createIssue`, `assignReviewer`, `mergePullRequest`。CRUD 汎用 `updateIssue` は作らない
- **認可は Policy 経由に統一**: mutation 内で `PermissionResolver` を直接呼ばない。RepositoryPolicy 等に `merge_pull_request?` のような verb を生やし、`authorize!(record, :merge_pull_request?, strict: false)` で payload errors として返す
- **Field 単位認可で `null` を返す**: 権限不足のリソースは GraphQL 上 `null` (HTTP は 200)。エラーは raise しない
- **`/graphql` は GET と POST の両方を受ける**: `urql` は queries に GET を使う (HTTP cache の活用)。Rails 側 `match "/graphql", via: %i[get post]`、CORS にも `methods: %i[get post options]`
- **Schema dump は CI で diff チェック**: `rake graphql:dump_schema` + `git diff --exit-code docs/schema.graphql`。OpenAPI の `committee-rails` に相当する乖離検知
- **Enum 命名衝突は許容してマップする**: 例えば `state: merged` と `mergeable_state: merged` は Rails enum 側で衝突するので Ruby 側は `merged_state` にし、GraphQL 側 (`graphql_name`) で `MERGED` に再マップする

### N+1 対策

- ADR が graphql-batch / Dataloader を掲げたら **`spec/graphql/n_plus_one_spec.rb` で計測する**: `ActiveSupport::Notifications.subscribed("sql.active_record")` でクエリを数え、件数 N に対してクエリが線形に増えないことを assert
- 例: `Sources::ViewerPermissionSource` 1 つで membership / team / collaborator を全 repo 横断で 1 度に取る (github)

### Frontend (urql + Next.js App Router)

詳細は [coding-rules/frontend.md](coding-rules/frontend.md#urql-provider-pattern) を参照。重要な点だけ：

- **Provider は Client Component**。`useState(() => createClient())` で 1 度だけ生成（モジュール singleton はマルチリクエスト SSR で危険）
- **`fetchOptions` は closure**: localStorage や cookie からの auth header 注入は fetch 時に毎回読み直す
- **codegen 出力は commit する**: `lib/gql/types.ts` を CI で diff チェック (schema dump と同じ思想)

### サンプルコード位置

- backend: `github/backend/app/graphql/` 一式
- frontend: `github/frontend/components/UrqlProvider.tsx`, `github/frontend/codegen.ts`
- N+1 spec: `github/backend/spec/graphql/n_plus_one_spec.rb`

---

## 現時点の宿題

- `slack/backend` と `youtube/backend` の OpenAPI 契約検証は導入済み (e94df38)
- ADR は **プロジェクト単位で 1 本** 起こす方針 (slack 0006, youtube 0007 = REST + OpenAPI、github 0001 = GraphQL)

---

## 関連ドキュメント

- [coding-rules/rails.md](coding-rules/rails.md) — Service オブジェクトと ai-worker 境界の共通方針
- [testing-strategy.md](testing-strategy.md) — request spec から OpenAPI を検証
- [operating-patterns.md](operating-patterns.md) — graceful degradation とエラーハンドリング規約
