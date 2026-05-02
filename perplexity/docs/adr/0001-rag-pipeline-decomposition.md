# ADR 0001: RAG パイプラインの分割方式

## ステータス

Accepted（2026-05-01）

## コンテキスト

`perplexity` プロジェクトの中核技術課題は **「ユーザのクエリに対し、ローカルコーパスから根拠を集めて引用付き回答を返す」** RAG パイプラインを実装すること。
パイプラインは概念的に **`retrieve → extract → synthesize`** の 3 ステージに分かれる:

- **retrieve**: クエリに関連する chunk を上位 N 件取り出す（hybrid scoring）
- **extract**: 取り出した chunk を「LLM に渡せる passage」に整形（位置・出典を保持）
- **synthesize**: passage を入力として answer を streaming 生成し、引用 id を埋める

このパイプラインを **どう分割するか** が本プロジェクト最大の設計分岐。
slack ADR 0001 (WebSocket fan-out) や youtube ADR 0001 (Solid Queue 状態機械) と同位の根幹判断にあたる。

制約:

- ローカル完結（外部 retriever / LLM API なし）
- 学習対象は **「Rails ↔ ai-worker の自然な責務分離」**。Python が担うべき計算 (BM25 / 数値類似度 / mock LLM) と Rails が担うべき制御 (永続化 / 認可 / 引用検証) を明示したい
- 引用整合性検証 (ADR 0004) は Rails 側で行う必要があり、各ステージの中間結果が Rails から見えていなければならない
- streaming は SSE で行う (ADR 0003)。stream するのは synthesize ステージだけで、retrieve / extract は 1 回の HTTP コールで完了する

## 決定

**「ai-worker に 3 つの独立したエンドポイント (`/retrieve` / `/extract` / `/synthesize/stream`) を置き、Rails が orchestrator として直列に呼ぶ」** を採用する。

- **Rails が orchestrator**: 1 query に対して 3 ステージを順番に呼び出し、各ステージの中間結果を `query_retrievals` 等の audit テーブルに記録する
- **`/retrieve`**: 同期 HTTP、入力 `{ query_text, top_k }` → 出力 `{ hits: [{ chunk_id, source_id, bm25_score, cosine_score, fused_score }] }`
- **`/extract`**: 同期 HTTP、入力 `{ chunk_ids }` → 出力 `{ passages: [{ source_id, snippet, ord }] }`
- **`/synthesize/stream`**: SSE、入力 `{ query_text, passages, allowed_source_ids }` → SSE event ストリーム (`chunk` / `citation` / `done`)
- **`allowed_source_ids` は retrieve 結果から Rails が組み立てて synthesize に渡す**: ai-worker は「この source 集合の外を引用してはならない」という制約を入力として受け取り、Rails は出力をその制約で再検証できる
- **chunk の本文 / embedding は ai-worker が DB から直接読む (読み専)**: Rails が JSON で chunk 本文を送り返す必要を消す。Rails は ID を渡すだけ。ベクタも MySQL の BLOB 列から ai-worker が直接 SELECT
- **embedding の書き込みは Rails 経由に統一 (一方向)**: corpus 取り込み時は Rails の seeds が `/corpus/embed` を呼んで embedding ベクトルを **JSON で受け取り**、Rails が `chunks.embedding` BLOB に保存。**ai-worker から DB への書き込みは禁止** (queries / answers / citations の書き込みも Rails 専担)
- 結果として、ai-worker ↔ MySQL は **読み専接続のみ** (`@@read_only` を強制するわけではないが、コード規約として `INSERT/UPDATE/DELETE` を ai-worker から発行しない)

## 検討した選択肢

### 1. 3 endpoint + Rails orchestrator ← 採用

- 各ステージが独立してテスト可能 (`/retrieve` だけ unit-test、`/synthesize/stream` だけ SSE 試験)
- 中間結果が Rails から見えるので audit / 引用検証が自然
- 将来 retriever を Faiss / OpenSearch に差し替える時、`/retrieve` だけ変えれば良い
- 欠点: 1 query で 3 HTTP コール = レイテンシ。学習用途では非問題

### 2. 単一 endpoint `/answer` (モノリシック)

- ai-worker が retrieve / extract / synthesize を内部で完結し、SSE で answer を返す
- 利点: HTTP 1 回で済む、レイテンシ最小
- 欠点: **中間結果が Rails 側に見えない**ので引用検証が ai-worker 内部に閉じる (ADR 0004 の信頼境界が引けない)
- 欠点: 各ステージのテストが synthesize 経由でしか書けない (重い)
- 欠点: Rails ↔ ai-worker の境界が薄まる (本プロジェクトの学習対象とズレる)

### 3. Rails 内で全部書く (Python 不使用)

- Ruby で BM25 + numpy 風の cosine + mock LLM を書く
- 利点: HTTP コール 0 回
- 欠点: **本リポの方針 (Rails / Python の責務分離)** から外れる。Python の数値計算スタックを学ぶ機会を捨てる
- 欠点: numpy 相当を gem (`numo-narray` 等) で埋めることになり、学習対象が逸れる

### 4. メッセージキュー経由の非同期パイプライン (Solid Queue / SQS 風)

- Rails が job を投げ、worker が retrieve→extract→synthesize を順次実行、結果を ActionCable で push
- 利点: 失敗リトライがしやすい、長時間処理に強い
- 欠点: SSE は **接続中の同期 HTTP 内で返す必要があり**、非同期 job との相性が悪い (ActionCable に切り替えると ADR 0003 の前提が崩れる)
- 欠点: 学習対象が "RAG パイプライン" ではなく "非同期 job + WebSocket" にズレる (slack で済んだ題材)

### 5. 並列実行 (`/retrieve` を BM25 / cosine で別 endpoint に分け fan-out)

- `/retrieve_bm25` と `/retrieve_vector` を並列に呼び、Rails 側で fused score を計算
- 利点: ベクタ retrieval のスケール時に効く (将来形)
- 欠点: 単一 endpoint で hybrid 計算を完結させた方が **「BM25 と cosine の重み統合をどこで決めるか」が明確**になる (ADR 0002)
- 欠点: 並列実行は Phase 2 完了後の最適化議論として残せる

### 6. ai-worker → backend の内部 ingress (REST + 共有トークン) で結果書き込みを行う

- `github` プロジェクト ([operating-patterns.md §7](../../../docs/operating-patterns.md#7-内部-trusted-ingress-rest--共有トークン)) で確立した規律：
  ai-worker が処理結果を内部 REST `POST /internal/...` で backend に書き込み、共有トークン認証
- 本プロジェクトに当てはめるなら:
  - ai-worker `/synthesize/stream` の `event: done` 時に `/internal/answers` に POST して永続化させる
  - ai-worker `/corpus/embed` の embedding を `/internal/chunks/:id/embedding` に直接 PUT する
- **採用しない理由**:
  - 本プロジェクトの synthesize は **SSE proxy 経路上で Rails が同期的に永続化できる** (`event: done` を Rails が受信した直後に `INSERT INTO answers / citations` する)。ai-worker が別経路で書き戻す動機が無い
  - 永続化と引用検証を **同一トランザクション**で行いたい (ADR 0004 の信頼境界)。書き込み経路が ai-worker → backend → DB に分かれると、検証境界が崩れる
  - 内部 ingress は **ai-worker が backend より先に状態を作る** ケース (github の `commit_checks` のように、AI が自律的に発火する) で価値が出る。本プロジェクトは **常に Rails の同期呼び出しの戻り値**として ai-worker が結果を返す形なので、内部 ingress は不要
- **結論**: 「読み専 (ai-worker → MySQL 直読)」+ 「書き込みは Rails 経由のみ」という非対称な境界を採用する。github との対比は ADR で意識的に却下した形で残す

## 採用理由

- **学習価値**: Rails ↔ ai-worker の境界が **3 ステージ × 入出力スキーマ** という具体的な形で残る。境界が薄いプロジェクト (slack の ai-worker は 1 endpoint) との対比が効く
- **アーキテクチャ妥当性**: 実 LangChain / LlamaIndex も retriever / chain / generator を独立コンポーネントとして組む。本プロジェクトの分割は実務スタックと整合
- **責務分離**: ai-worker = 純粋な計算 (検索 / 整形 / 生成)、Rails = 永続化 / 認可 / 引用検証。**信頼境界が Rails 側に置ける** (ADR 0004 の前提)
- **テスタビリティ**: 各 endpoint が単体で curl/pytest できる。`/synthesize/stream` の SSE 試験も独立に書ける
- **将来の拡張性**: retrieve だけ Faiss に差し替え / extract に reranker を挟む / synthesize を本物の LLM API に差し替え、いずれも他ステージに波及しない

## 却下理由

- 単一 `/answer` モノリシック: 引用検証が ai-worker 内部に閉じ、信頼境界が引けない (ADR 0004 と矛盾)
- Rails 内で全部: Python の数値計算を捨てる、本リポの責務分離方針と逆行
- 非同期キュー: SSE と相性が悪く、学習対象が slack で済んだ非同期 job 寄りに偏る
- BM25 / cosine の並列 fan-out: 現スコープでは過剰、Phase 2 完了後の最適化議題として残す
- 内部 ingress (ai-worker → backend 書き戻し): 本プロジェクトの同期 SSE proxy 経路では Rails が直接永続化できるので不要。github との対比として「ai-worker が自律発火するケースでない」という違いをコードで示す

## 引き受けるトレードオフ

- **3 HTTP コール / クエリ**: ローカル開発でレイテンシは数十 ms オーダー、学習用途では問題ない。本番化時は `/retrieve` と `/extract` を統合する余地がある (ADR 派生で扱う)
- **JSON 往復のオーバーヘッド**: chunk の本文は ai-worker が DB から直接読むことで、JSON ペイロードは ID 配列のみに抑える
- **DB アクセス権限の二系統**: ai-worker は読み専、Rails は読み書き。SQLAlchemy 側で `INSERT/UPDATE/DELETE` を使わない規約を pytest で確認 (`test_ai_worker_db_readonly.py`)。MySQL ユーザを 2 つ立てて DDL レベルで分離する案は **ローカル完結方針に対して過剰**として採らず、コード規約で守る
- **信頼境界の二重化**: ai-worker は `allowed_source_ids` を受け取り「この外は引用しない」を assert (warn) するが、最終検証は Rails で行う (二重チェック)。ai-worker のバグが Rails の検証を素通りしないための保険
- **Rails が長時間 SSE を保持**: `/synthesize/stream` を proxy する間、Rails の puma worker が 1 つ占有される。本番では Falcon / Iodine 系のイベント駆動サーバを検討 (Terraform に注記)
- **失敗リトライなし**: SSE 中の切断は answer.status=failed で即終了。再生成は frontend からの再リクエスト扱い
- **`query_retrievals` は失敗後も残す (audit)**: retrieve は成功したが extract / synthesize が失敗した場合、`query_retrievals` 行は **意図的に残す**。「LLM に何が渡されたか / どの chunk が allowed_source_ids 集合に入る予定だったか」の証跡として価値があるため。query.status=failed と組み合わせて「retrieve は通ったが後段で失敗」というケースが事後に再現可能になる。テストは `rag_orchestrator_spec` の "ai-worker fails on extract" / "ai-worker fails on synthesize" で固定。

## このADRを守るテスト / 実装ポインタ（Phase 2 以降で実装）

- `perplexity/ai-worker/main.py` — 3 endpoint の FastAPI ルーティング
- `perplexity/ai-worker/services/retriever.py` — `/retrieve` のロジック (hybrid scoring は ADR 0002)
- `perplexity/ai-worker/services/extractor.py` — `/extract` のロジック
- `perplexity/ai-worker/services/synthesizer.py` — `/synthesize/stream` の mock LLM SSE
- `perplexity/backend/app/services/rag_orchestrator.rb` — 3 ステージを順次呼ぶ Rails 側 orchestrator
- `perplexity/backend/app/controllers/queries_controller.rb#stream` — `ActionController::Live` で SSE proxy
- `perplexity/backend/app/models/query_retrieval.rb` — 中間結果の audit 永続化
- `perplexity/backend/spec/services/rag_orchestrator_spec.rb` — 3 ステージの順序 / 中間結果保存
- `perplexity/ai-worker/tests/test_endpoints.py` — 各 endpoint の独立試験

## 関連 ADR

- ADR 0002: Hybrid retrieval（`/retrieve` の中身）
- ADR 0003: SSE streaming プロトコル（`/synthesize/stream` の伝送方式）
- ADR 0004: 引用整合性の検証境界（このパイプライン上で誰が citation を信用するか）
