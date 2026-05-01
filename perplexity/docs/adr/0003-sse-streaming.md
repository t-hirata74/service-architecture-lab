# ADR 0003: ストリーミングプロトコルとして SSE を採用

## ステータス

Accepted（2026-05-01）

## コンテキスト

Perplexity 風 UX の中核は **「answer がタイプライター効果で逐次表示され、引用が後追いで貼られる」** こと。サーバ側で生成された文字列を、確定した端から frontend へ流す経路が必要になる。

本リポジトリではすでに 3 通りのリアルタイム / 準リアルタイム伝送を扱った:

- `slack`: WebSocket (ActionCable + Redis Pub/Sub) — 双方向 fan-out
- `youtube`: 同期 REST のみ (status は polling)
- `github`: 同期 REST + 5s polling for CI badge

このプロジェクトでは **既存と差別化した** 4 つ目のパターンを学びたい。
そして RAG の synthesize ステージは:

- **単方向 (server → client)** で十分
- **long-lived な 1 query / 1 接続**
- **テキストイベント (チャンクと citation)** を順に流す
- **HTTP infrastructure (CORS / auth header / proxy) と整合する**ことが望ましい

これらの性質に最も自然に噛み合うのが **Server-Sent Events (SSE)**。

制約:

- ローカル完結 (Cloudflare Workers / SSE 専用ブローカは使わない)
- Rails 8 / Next.js 16 で素直に書ける構成
- Rails 側で ai-worker からの SSE を **proxy** する必要がある (引用検証のため、ADR 0004)
- frontend では **auth header (Authorization Bearer 等)** を SSE 接続に乗せたい (`EventSource` API の制約と関連)

## 決定

**「Server-Sent Events (SSE) over HTTP/1.1 を `ActionController::Live` で実装、frontend は `fetch` + ReadableStream で受信」** を採用する。

### Backend (Rails)

- `QueriesController#stream` で `include ActionController::Live`
- `response.headers["Content-Type"] = "text/event-stream"`、`Cache-Control: no-cache`、`X-Accel-Buffering: no` (Nginx バッファ無効化)
- ai-worker の `/synthesize/stream` を **`Net::HTTP` の chunked read** で受け、行単位でパースしながら `response.stream.write` で frontend に転送
- 各 chunk が来るたびに **引用 ID を正規表現 (`/\[#(src_\d+)\]/`) で抽出**、Rails 側の `allowed_source_ids` (retrieve 結果由来) と照合 (詳細は ADR 0004)
- 終了は `event: done` を受信したら `response.stream.close`、`answers` / `citations` を MySQL に永続化

### イベント形式

```
event: chunk
data: {"text": "東京タワーは ", "ord": 0}\n\n

event: chunk
data: {"text": "1958 年に [#src_3] 完成した。", "ord": 1}\n\n

event: citation
data: {"marker": "src_3", "source_id": 42, "chunk_id": 117, "valid": true}\n\n

event: citation_invalid
data: {"marker": "src_99", "reason": "not_in_allowed_source_ids"}\n\n

event: done
data: {"answer_id": 7, "citations": [{"marker":"src_3","source_id":42}]}\n\n
```

- 1 イベントは `event:` + `data:` + 空行で区切る (SSE 仕様)
- `data:` は **JSON 1 行**で送る (改行は `\n` を JSON 文字列内でエスケープ)
- frontend が再接続できるように、長時間 (>15s) chunk が来ない場合は `:keepalive` コメント行を送る

### Frontend (Next.js)

- **`fetch` + ReadableStream を採用、`EventSource` は使わない**
- 採用理由は **「`AbortController` で明示的に中断できる」「将来 Authorization header が要る場合 (rodauth-rails 以外の auth に切り替えた場合) に困らない」「ストリーム消費フックを汎用化しやすい」** の 3 点
- (rodauth-rails の cookie auth で済むので EventSource でも auth は通るが、UX 制御 / 将来性 / 学習価値で fetch を選ぶ)
- `fetch('/queries/123/stream', { credentials: 'include', signal: controller.signal })` の `response.body` を `getReader().read()` でループ
- 受け取った Uint8Array を TextDecoder でデコード、SSE フォーマットを自前パース (区切り `\n\n`、`event:` / `data:`)
- **失敗時は再接続せず即終了**: `event: error` を受け取ったら stream を close、ユーザに「再生成」ボタンを提示。answer は `status: failed` で永続化済み
  - `Last-Event-ID` ベースの自動再接続は **本プロジェクトでは扱わない**: ADR 0001 の「失敗即終了 / 再生成は再リクエスト」と整合する形で、本 ADR からも削除する判断

### 認可

- SSE 開始時 (`GET /queries/:id/stream`) で `query.user_id == current_user.id` を確認
- 不一致なら 404 (slack / youtube と整合: visibility 不一致は 404)

### graceful degradation 規律 (SSE 三段階)

[`docs/operating-patterns.md` §2 の「外部依存失敗時は 200 + degraded」](../../../docs/operating-patterns.md#2-graceful-degradation) は **HTTP body 送信前のレスポンス** が前提で、SSE は途中で HTTP status を変えられないため別規律が必要。本プロジェクトでは **SSE のライフサイクル 3 段階** で振る舞いを決める:

| 段階 | タイミング | 失敗時の振る舞い |
| --- | --- | --- |
| **(A) SSE 開始前** | retrieve / extract のいずれか / SSE 接続 establish 前まで | **HTTP 5xx を素直に返す** (200 + degraded ではなく)。retrieve 失敗は `503 + { error: "retrieval_unavailable" }`、`Content-Type: application/json`。frontend は SSE を開始しない |
| **(B) SSE 開始後 / done 前** | `event: chunk` を 1 つでも送った後の synthesize 中断 | `event: error data: { reason }` を送って `response.stream.close`。answer.status を `failed` に UPDATE。**citations は 1 件も永続化しない** (途中まで insert を許すと検証境界が崩れる) |
| **(C) done 受信後** | ai-worker `event: done` を受信した後の Rails 側 INSERT 失敗 | `event: error` を frontend に送り、answer は `failed` で永続化失敗扱い。frontend は再生成導線を提示 |

> retrieve / extract は (A) 段階なので **operating-patterns.md §2 と整合**: ai-worker 不通時は Rails が `503` を返し、frontend は SSE を開かずに「現在検索が利用できません」を表示。
> synthesize 中断 (B) は本プロジェクト固有の例外規律として ADR で固定する。`event: error` の `data` には `reason: "ai_worker_disconnect" | "ai_worker_timeout" | "internal_error"` の 3 種を使う。

**永続化の原子性**: `event: done` を受けた Rails は `Answer.transaction do INSERT answer; INSERT citations END` で 1 トランザクションに包む。途中失敗時に citations だけ残ることを防ぐ (本プロジェクトの引用整合性を満たす最低条件、ADR 0004 と整合)。

## 検討した選択肢

### 1. SSE + ActionController::Live + fetch ReadableStream ← 採用

- 単方向 long-lived ストリームに最も素直
- HTTP infrastructure (CORS / proxy / auth) と整合
- `EventSource` を捨てて `fetch` ReadableStream にすることで auth header と CORS credential 問題を回避
- 欠点: Rails の puma worker が 1 接続に張り付く

### 2. WebSocket (ActionCable + Redis Pub/Sub)

- slack で扱った構成。双方向通信が前提
- 欠点: **slack と完全に同じスタック** → 学習価値が薄い (本リポでの差別化が消える)
- 欠点: 双方向不要なドメインで WebSocket を選ぶのは過剰
- 欠点: Redis 依存が増え、docker-compose が膨らむ (本プロジェクトは MySQL のみで済ませたい)

### 3. GraphQL Subscription (graphql-ruby + AnyCable / ActionCable)

- 利点: github の GraphQL 採用と整合
- 欠点: Rails の subscription 実装は ActionCable 経由が標準で、結局 WebSocket スタックを再現することになる
- 欠点: Phase 1 の決定として REST + SSE の方が薄い (graphql-ruby を入れない判断は別 ADR で扱う)
- 欠点: ai-worker → Rails の中継部分が GraphQL では書きにくい (REST proxy の方が単純)

### 4. Long polling

- 利点: 最も枯れた技術
- 欠点: タイプライター UX が破綻 (細かいレイテンシで再接続コストが嵩む)
- 欠点: 教育的にも 2026 年に新規プロジェクトで long polling を選ぶ理由がない

### 5. HTTP/2 server push

- 利点: 過去に検討された方式
- 欠点: ブラウザ側の実装が deprecated (2022 以降 Chrome / Firefox とも off by default)
- 欠点: 採用情報の更新が止まっている

### 6. gRPC streaming

- 利点: production grade で双方向 / 単方向 stream が綺麗に書ける
- 欠点: ブラウザネイティブで動かない (gRPC-Web を挟む必要)
- 欠点: 学習対象がプロトコル選定に偏り、RAG の本題から外れる

### 7. Rails の ActionCable で SSE を擬似する

- 不可: ActionCable は WebSocket 専用。SSE には使えない

## 採用理由

- **学習価値**: 「単方向 long-lived HTTP ストリーム」という SSE の典型ユースケースを正面から扱える。WebSocket / polling との対比が rep 横断で残る
- **アーキテクチャ妥当性**: OpenAI / Anthropic / Perplexity 等の LLM API は SSE がデファクト。実 LLM 製品の通信形式と整合
- **責務分離**: ai-worker の `/synthesize/stream` も SSE → Rails が SSE → frontend という統一フォーマットで proxy が単純
- **HTTP インフラとの相性**: CORS / 認証 / reverse proxy / observability すべて HTTP の延長で対応できる
- **将来の拡張性**: 引用以外のメタイベント (`event: progress`, `event: tool_use`) を追加しても仕様が壊れない

## 却下理由

- WebSocket / GraphQL Subscription: slack で扱ったスタックの再演 + Redis 依存
- Long polling: UX が破綻、新規採用する理由がない
- HTTP/2 server push: ブラウザサポートが死んでいる
- gRPC streaming: ブラウザ非対応 / 学習対象がズレる

## 引き受けるトレードオフ

- **puma worker の占有**: 1 SSE = 1 worker thread を保持。デフォルト 5 worker × 5 thread = 25 同時 SSE が上限。学習用途では十分。本番化時は Falcon / Iodine / nginx + Rack hijack に切り替える余地を Terraform で示す
- **`ActionController::Live` の挙動**: Rails の通常 controller と異なり Rack hijack 系で動く。**transactional fixtures が一部効かない**、Active Record の thread connection を `clear_active_connections!` で明示的に解放する必要 — テスト戦略として ADR 0005 で扱う
- **proxy のバッファリング**: nginx / cloudflare はデフォルトで SSE をバッファする。`X-Accel-Buffering: no` と `Cache-Control: no-cache` を必ず付ける
- **再接続なし (失敗即終了)**: `EventSource` 標準の自動再接続を捨て、`Last-Event-ID` も使わない。再生成は frontend からの再 POST 扱い (ADR 0001 の "失敗リトライなし" と整合)
- **エラーハンドリング**: SSE は HTTP ステータスを途中で変えられない。**SSE 開始前** は素直に 5xx (上記 graceful degradation §A)、**SSE 開始後** は `event: error` (上記 §B / §C)
- **CORS preflight**: `fetch` + ReadableStream は `Authorization` header を持つと preflight が走る。Rails 側で `OPTIONS` 返却を追加 (`rack-cors` で対応)
- **observability**: Rails のログにストリームの内容が flood しないよう、SSE handler 専用のログレベル + chunk ごとの `logger.debug` 抑制を設定

## このADRを守るテスト / 実装ポインタ（Phase 4 以降で実装）

- `perplexity/backend/app/controllers/queries_controller.rb#stream` — `include ActionController::Live` の SSE handler
- `perplexity/backend/app/services/sse_proxy.rb` — ai-worker からの chunked HTTP を行単位でパースして転送する PORO
- `perplexity/backend/spec/requests/queries_stream_spec.rb` — `Net::HTTP` で SSE を読み、`event:` と `data:` のシーケンスを assert
- `perplexity/ai-worker/services/synthesizer.py` — FastAPI `StreamingResponse` で SSE を吐く
- `perplexity/ai-worker/tests/test_synthesizer_stream.py` — yield 順 (chunk × N → done) と event 形式の assert
- `perplexity/frontend/lib/sse.ts` — `fetch` + ReadableStream で SSE をパースする hook
- `perplexity/playwright/tests/streaming.spec.ts` — クエリ送信 → タイプライター効果で answer が出る → 引用ハイライト

## 関連 ADR

- ADR 0001: RAG パイプライン分割 (synthesize ステージのみが stream 対象)
- ADR 0004: 引用整合性検証 (SSE proxy 中に Rails が citation を抽出して検証)
- ADR 0005: テスト戦略 (`ActionController::Live` の RSpec での扱い)
- slack ADR 0001: WebSocket fan-out (本 ADR の対比相手)
- リポジトリ共通: [operating-patterns.md §2](../../../docs/operating-patterns.md#2-graceful-degradation) — SSE は本 ADR 内で例外規律を持つ
