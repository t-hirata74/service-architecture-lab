# ADR 0005: テスト戦略

## ステータス

Accepted（2026-05-01）

## コンテキスト

`perplexity` のテストは **3 つの非自明な領域** を抱える:

1. **`ActionController::Live` を使った SSE エンドポイント** (ADR 0003) — Rails の通常 controller 試験パターンが効かない
2. **hybrid retrieval の数値的正しさ** (ADR 0002) — 「BM25 と cosine の min-max 正規化 + 重み付き和」が α 境界 / 退化ケース / top-k cut で意図通りに動くこと
3. **引用整合性の Rails 側再検証** (ADR 0004) — SSE proxy 中の partial buffering / regex 抽出 / `allowed_source_ids` 照合の 3 つが正しく合成されること

slack / youtube / github はそれぞれの主要技術課題に応じてテスト構成を作ったが (slack=ActionCable + Capybara、youtube=Solid Queue + RSpec request、github=GraphQL N+1 spec)、本プロジェクトは **SSE / hybrid retrieval / citation 検証** を扱う以上、それらのいずれとも違う形になる。

> 本 ADR は **テストツールチェーンの選定** ではなく **「SSE / hybrid scoring / citation 検証をどうテストするか」** の方針確定が目的。
> ツール (RSpec / pytest / Playwright) は既存プロジェクトを踏襲する。

制約:

- `ActionController::Live` は **Rack hijack 系** で動き、Rails の通常 request spec と挙動が異なる
- Capybara / Capybara-WebKit / RSpec system spec は SSE のような **長時間 HTTP ストリーム** をネイティブで読めない
- ai-worker の `/synthesize/stream` は FastAPI の `StreamingResponse` で SSE を吐くので、Python 側のテストも sync request では足りない
- E2E は本リポ全体で Playwright (chromium) を採用済み — `fetch` + ReadableStream の SSE 消費は Playwright の `page.evaluate` で実装可能

## 決定

**「SSE は `Net::HTTP` / `httpx` の素の chunked read で event 列を assert、retrieval / citation の論理は純関数 unit-test、E2E は Playwright で fetch ReadableStream を使う 3 層構成」** を採用する。

### 1. Rails backend (RSpec)

| テスト種別 | フレームワーク / 実装 | 対象 |
| --- | --- | --- |
| **モデル / サービス unit** | `rails_helper.rb` + FactoryBot | `Query` / `Answer` / `Citation` モデル / `RagOrchestrator` / `CorpusIngestor` / `CitationValidator` |
| **request spec (REST)** | `rails_helper.rb` (transactional fixtures ON) | `POST /queries` / `GET /queries/:id` / 認可 / graceful degradation §A (5xx 系) |
| **SSE spec** | **`Net::HTTP` を生で使う custom helper** (transactional fixtures OFF / DatabaseCleaner truncation) | `GET /queries/:id/stream` の event 列 (`chunk` / `citation` / `done`) / 認可 / graceful degradation §B (`event: error`) / 永続化原子性 (citations 0 件 OR all) |
| **citation validator unit** | RSpec | regex 抽出 / `allowed_source_ids` 照合 / partial buffering (chunk 境界またぎ) / unicode escape / code block 内の marker らしき文字列 |

**SSE spec 設計の要点**:

- `include ActionController::Live` の controller は **transactional fixtures で wrap できない** (別 thread が DB connection を別途取るため). `Rails.application.config.active_job.queue_adapter` 系の問題ではなく **DB connection の thread 越境** が原因
- 解決策: SSE spec ファイル冒頭で `self.use_transactional_tests = false` + `DatabaseCleaner.strategy = :truncation` を有効化
- `Net::HTTP.start(host, port) { |http| http.request_get(path) { |res| res.read_body { |chunk| ... } } }` の chunk callback で SSE event を 1 行ずつパース
- ai-worker は **WebMock + chunked response stub** で固定値を返させる: `stub_request(:post, "http://localhost:8030/synthesize/stream").to_return { |_| { body: sse_fixture, headers: { "Content-Type" => "text/event-stream" } } }` + body を IO で返すパターン (Phase 4 の helper として整備)
- 各 spec は **接続 establish 前 / event:chunk 1 件後 / event:done 後** の 3 タイミングで failure injection を行い、graceful degradation 三段階 (ADR 0003) を網羅

### 2. ai-worker (pytest)

| テスト種別 | 対象 |
| --- | --- |
| **score_fusion unit** | min-max 正規化 / α 境界 (0 / 0.5 / 1) / 全件同点退化 / top-k cut |
| **encoder unit** | deterministic 性 (同入力で同出力) / `version()` 文字列 / 256 次元 / float32 dtype |
| **retriever integration** | sqlite or MySQL test DB に固定 chunk を投入し、既知クエリで上位が期待 chunk になること |
| **synthesizer SSE** | `httpx.AsyncClient` + `async for chunk in response.aiter_bytes()` で SSE event 列を assert |
| **DB readonly guard** | ai-worker から `INSERT/UPDATE/DELETE` が発行されないことを SQLAlchemy event hook で確認 (ADR 0001 の規約) |

**SQLAlchemy session 制約**: Rails と ai-worker が同一 MySQL に同時に書き込まないことは ADR 0001 で決めたが、テストでは Rails 側の `chunks` 行に対して ai-worker が SELECT し、書き込まないことを確認。session を `with engine.connect() as conn:` で raw SQL を流すパターン (ORM の sticky transaction を避ける)

### 3. E2E (Playwright)

| シナリオ | 確認 |
| --- | --- |
| **golden path** | クエリ送信 → SSE で typewriter 効果 → 引用 marker がハイライト表示 → 引用クリックで source preview が出る |
| **citation invalid** | mock LLM が allowed 外の id を吐くケース (固定 fixture モード) → 該当 marker は薄字 (クリック不可) でレンダ、本文には残る (ADR 0004) |
| **graceful degradation §A** | ai-worker `/retrieve` を 503 にしておく → frontend は SSE を開かずエラーバナー表示 |
| **graceful degradation §B** | ai-worker `/synthesize/stream` が途中で切断 → `event: error` 受信 → 「再生成」ボタンが出る、answer.status = failed |

**Playwright での SSE 消費**: `EventSource` は使わないので、`page.evaluate` で `fetch + ReadableStream` を駆動し、受信 event 数 / 内容を `window.__sseLog` 経由で取り出す。タイプライター効果は `await expect(page.locator(...)).toHaveText(/.../)` の段階的進行で待機。

### 4. CI

- `perplexity-backend`: MySQL サービス起動 → `db:create db:migrate` → RSpec (transactional + SSE spec)
- `perplexity-frontend`: ESLint + TypeScript + Next.js build
- `perplexity-ai`: pip install + pytest + uvicorn boot smoke (wait-loop で flake 防止)
- `perplexity-terraform`: fmt + init + validate
- 既存 12 ジョブ + 4 ジョブ = **計 16 ジョブ並列**

## 検討した選択肢

### 1. Net::HTTP / httpx 直叩き + 純関数 unit + Playwright ← 採用

- SSE は HTTP の素の chunked read で扱える (raw に近い)
- 各層が独立: validator / score_fusion / synthesizer は SSE と切り離してテスト可能
- 欠点: SSE spec helper の自前実装コスト (Phase 4 で 30〜50 行程度)

### 2. Capybara system spec で headless chrome から SSE を読む

- 利点: 1 spec で UI まで通せる
- 欠点: **SSE の event 列を厳密に assert しにくい** (DOM 状態経由の試験になり、`event: citation_invalid` の検出が間接的になる)
- 欠点: spec が遅くなる (chrome 起動コスト)
- → E2E (Playwright) で別途網羅するので、RSpec 側は HTTP 直叩きに割り切る

### 3. SSE 専用テスト gem (`rspec-sse`, `action_cable_testing` 相当)

- 該当する gem が成熟していない (2026-05 時点)
- ActionCable テスト helper は WebSocket 専用、SSE には使えない
- → 採用するなら自作 helper のみが現実的

### 4. mock LLM を ai-worker 側でなく Rails 側で stub

- 利点: Rails の SSE spec が ai-worker を起動せずに完結する
- 欠点: ADR 0001 の「Rails ↔ ai-worker 境界」を試験できない (HTTP 経由の振る舞いが見えない)
- → WebMock で ai-worker を mock する方が境界の試験になる

### 5. Pact / Schemathesis での contract test

- 利点: ai-worker と Rails の API 契約を schema で固定できる
- 欠点: SSE はスキーマ駆動と相性が悪い (event 列の順序まで OpenAPI で表現しづらい)
- → Phase 5 完了後の派生 ADR で扱える題材

## 採用理由

- **学習価値**: 「SSE のテストをどう書くか」は Web 開発で扱う頻度が増えているのにドキュメントが薄い領域。本 ADR で形を固定することで、本リポの後続 streaming プロジェクトの土台になる
- **責務分離**: 数値的正しさ (score_fusion / validator) と通信プロトコル (SSE) を別レイヤで試験する分割が一直線
- **既存スタックの踏襲**: RSpec / pytest / Playwright は本リポで標準化済み。新規ツール導入を避ける
- **再現性**: WebMock + chunked response stub により ai-worker 不在で Rails の SSE spec が走る (CI で fan-in しない)

## 却下理由

- Capybara system spec: SSE event 列の厳密 assert が困難
- 専用 SSE gem: 成熟していない
- Rails 側で LLM stub: 境界テストが消える
- Contract test: SSE 順序保証と OpenAPI の相性、Phase 5 完了後の課題

## 引き受けるトレードオフ

- **`use_transactional_tests = false` の SSE spec はテスト分離コストが上がる**: DatabaseCleaner truncation で前後を清掃する必要、並列実行でデッドロック risk があるので `parallel_tests` 採用時は SSE spec を直列化する
- **WebMock の SSE stub helper を Phase 4 で書く必要**: 30〜50 行のヘルパー追加。`spec/support/sse_helper.rb` に集約
- **Playwright で `EventSource` を使わない**: ReadableStream を `page.evaluate` で駆動する自前 helper を Phase 5 で書く
- **ai-worker pytest の DB セットアップ**: SQLAlchemy で MySQL test DB に接続するセットアップコストが pytest fixture で発生 (Rails の `db:test:prepare` 後に pytest を流す前提で CI を組む)
- **flaky risk**: SSE spec は thread / IO timing 依存なので flake が出やすい。**timeout / chunk wait の閾値は generous に**（ローカル 2s / CI 5s）取る方針を Phase 4 着手時に固定
- **citation_invalid の確率的振る舞いは fixture モードで固定**: mock LLM がランダムに allowed 外 id を吐くと再現性が崩れる。**`SYNTHESIZER_FIXTURE=invalid` env で固定 fixture を返す経路**を Phase 4 で実装

> **Phase 3 → Phase 4 のテスト戦略移行 (実装注)**:
> - Phase 3 の `AiWorkerClient#synthesize_stream` (SSE 同期消費 + event 配列返却) は **Phase 4 で捨てる**.
>   Controller の `ActionController::Live` が ai-worker への chunked HTTP を直接読み、frontend に
>   stream-proxy する形に書き直す。これにより `rag_orchestrator_spec` で SSE event を WebMock の
>   chunked body で渡している既存テストは **Phase 4 で全面的に書き換える**必要がある.
> - Phase 4 では SSE event 列の試験は **Net::HTTP 直叩きで Rails の SSE エンドポイント**を読む
>   形に変える (`spec/support/sse_helper.rb` を新規追加予定 / 上記実装ポインタに記載済み).
> - 移行時に壊れるテストの想定範囲は事前に把握済み: `rag_orchestrator_spec.rb` の `stub_synthesize_sse`
>   系 5 spec / `queries_spec.rb` の orchestrator 経由 spec。これらは Phase 4 着手の最初の 1-2 commit
>   で書き換える計画 (Phase 3 は **同期 RAG として完結**しており、Phase 4 への移行で同期経路を
>   削除しても他テスト (chunker / corpus_ingestor / model 系 56 件) には波及しない).

## このADRを守るテスト / 実装ポインタ（Phase 2 以降で実装）

- `perplexity/backend/spec/rails_helper.rb` — RSpec base config
- `perplexity/backend/spec/support/sse_helper.rb` — `Net::HTTP` で SSE event を読むヘルパー (Phase 4 で追加)
- `perplexity/backend/spec/support/webmock_sse_stub.rb` — chunked response の stub helper
- `perplexity/backend/spec/requests/queries_stream_spec.rb` — SSE event 列 assert (transactional OFF)
- `perplexity/backend/spec/services/citation_validator_spec.rb` — 純関数 unit
- `perplexity/backend/spec/services/rag_orchestrator_spec.rb` — retrieve / extract / synthesize の順序と中間結果保存
- `perplexity/ai-worker/tests/conftest.py` — pytest fixture (DB / WebMock / encoder)
- `perplexity/ai-worker/tests/test_score_fusion.py` — α 境界 / 退化 / top-k
- `perplexity/ai-worker/tests/test_synthesizer_stream.py` — `httpx.AsyncClient` で event 列 assert
- `perplexity/ai-worker/tests/test_ai_worker_db_readonly.py` — INSERT/UPDATE/DELETE 不発行ガード
- `perplexity/playwright/tests/streaming.spec.ts` — golden path + citation_invalid + graceful degradation §A/§B

## 関連 ADR

- ADR 0001: RAG パイプライン分割 (DB readonly 規約の試験対象)
- ADR 0002: hybrid retrieval (score_fusion / encoder の数値試験対象)
- ADR 0003: SSE streaming (本 ADR の試験対象の中核)
- ADR 0004: 引用整合性 (citation_validator の試験対象)
- リポジトリ共通: [testing-strategy.md](../../../docs/testing-strategy.md) — 本 ADR は SSE / hybrid scoring / citation の 3 領域を補完する形
