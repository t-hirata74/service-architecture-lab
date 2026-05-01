# ADR 0002: Hybrid retrieval（BM25 + 擬似ベクタ類似度）

## ステータス

Accepted（2026-05-01）

## コンテキスト

`/retrieve` ステージ (ADR 0001) で「クエリに関連する chunk を上位 N 件取り出す」ための検索方式を決める必要がある。

> **学習対象の明確化**: 本 ADR の学習対象は **「hybrid scoring の構造 / embedding の永続化と再計算 / cold start ロード」** であって、**意味類似度の精度ではない**。
> ローカル完結方針の下で擬似 encoder を使う以上、cosine 類似度の絶対値は本物の sentence-transformers ほど機能しない。
> 「この設計で精度が出る」と読まれないように、本 ADR は **構造とデータ管理** を訴求軸にする。

学習対象として欲しい性質:

- **hybrid scoring の構造**: BM25 (語彙一致) と cosine (擬似ベクタ) を **どう正規化し / どう統合するか** をコードで読める形に残す
- **embedding データ管理**: BLOB 永続化 / `embedding_version` 不一致時の再計算トリガ / cold start での numpy in-memory ロード — youtube ADR 0004 の FULLTEXT のみでは扱われなかった「ベクタ系データ運用」の論点
- **ローカル完結**: OpenSearch / Faiss / pgvector のような重量級ストアは入れない
- **youtube との差分**: youtube ADR 0004 で FULLTEXT (ngram) は学習済み。本 ADR の差分は **(a) 重み統合のロジック / (b) embedding の BLOB 永続化と versioning / (c) ai-worker の cold start ロード戦略** の 3 つ

制約:

- DB は MySQL 8 で揃える (slack / youtube / github と整合)
- Python 側で numpy が使える前提
- コーパスは数百〜数千件規模を想定 (本物の Web 規模は対象外)
- 埋め込みは外部 API を使えないので **擬似 encoder** で生成する (本物の意味類似は出ない、これは意図した制約)

## 決定

**「BM25 (MySQL FULLTEXT ngram) + 擬似ベクタ cosine 類似度の重み付き和を採用、計算は ai-worker 側に集約」** とする。

### 検索方式の構成

1. **BM25 段**: MySQL の `FULLTEXT INDEX (title, body) WITH PARSER ngram` に対して `MATCH ... AGAINST(? IN BOOLEAN MODE)`。MySQL が返すスコアを `bm25_score` として使う
2. **ベクタ段**: chunk テーブルに `embedding BLOB`（float32 × 256 次元 = 1024 byte）を持たせ、ai-worker は **コーパス全 chunk の embedding を numpy 配列に in-memory ロード**。クエリ embedding との cosine 類似度を一括計算
3. **スコア統合**: 両段のスコアを **min-max 正規化**してから重み付き和:
   ```
   fused_score = alpha * bm25_norm + (1 - alpha) * cosine_norm
   ```
   `alpha = 0.5` を初期値とし、env / settings で差し替え可能にする
4. **top-K**: fused_score 降順で上位 10 件 (`top_k` パラメタで上書き可) を返す

### 擬似 encoder の方針

ローカル完結の制約から、**deterministic な疑似 encoder** を ai-worker 側に置く:

- 入力テキストを字単位 / token 単位で hash → 256 次元の float32 ベクトルに射影
- 同じ入力 → 必ず同じ embedding (再現性)
- **意味的類似度の精度は出ない**ことを ADR で明記。学習対象は "ベクタ計算とスコア統合の構造" であり、本物の埋め込みモデル品質ではない
- 本物の sentence-transformers をローカルで動かす案は **ローカル完結方針には沿うが学習スコープを越える** ため不採用 (派生 ADR で扱う余地は残す)

### コーパスの取り込み (embedding 書き込みフロー)

ai-worker の DB 書き込み権限を持たせない (ADR 0001) 制約から、**embedding の生成は ai-worker、永続化は Rails 経由** で統一する:

1. `seeds.rb` (or `rake corpus:ingest`) が `sources` を作成
2. Rails が source を chunk に分割 (固定長戦略は ADR 0006)、`chunks` を `embedding=NULL`, `embedding_version=nil` で先に INSERT
3. Rails が ai-worker `POST /corpus/embed` に `{ chunk_id, text }` を投げ、`{ embeddings: [[float; 256]] }` を JSON で受け取る
4. Rails が `chunks.embedding` (BLOB) と `embedding_version` を UPDATE
5. ai-worker は startup hook で `SELECT id, embedding FROM chunks WHERE embedding_version = current` を全件 numpy にロード (cold start)

> **embedding の絶対値 ↔ 浮動小数点の往復**: ai-worker は float32 配列を JSON で返し、Rails は `Array#pack("g*")` で little-endian float32 BLOB に詰める。読み戻す ai-worker 側は `numpy.frombuffer(blob, dtype="<f4")`。**byte 順を `<` (little-endian) で固定**、`embedding_version` 列で encoder 仕様を tag。

### 再計算トリガ

擬似 encoder の実装を変えると `embedding_version` が変わる。**`rake corpus:reembed` を提供** し、`embedding_version` 不一致 / NULL の chunk を再 embed する。startup 時の自動再計算は **しない** (起動時間が予測不能になるため)。chunk 数 × 数百 ms オーダーの作業を CLI 起動の意思決定に紐付ける。

## 検討した選択肢

### 1. BM25 + 擬似ベクタ hybrid (numpy in-memory) ← 採用

- 利点: hybrid scoring が学習対象として教科書通りに書ける
- 利点: 外部依存なし、コーパス数千件規模なら numpy in-memory で十分
- 利点: youtube の FULLTEXT を一歩進めて「正規化 + 重み統合」を実装する経験になる
- 欠点: 擬似 encoder なので意味類似度の精度は低い (学習目的では非問題)

### 2. BM25 only

- 利点: 最小実装、youtube と完全に同じスタック
- 欠点: **hybrid 議論を学べない**。本プロジェクトの差別化点 (youtube から一歩進める) を消す
- 欠点: 言い換えクエリでヒット 0 件になり、SSE デモが映えない

### 3. ベクタ only

- 利点: 純粋な ANN search を学べる
- 欠点: 擬似 encoder の精度では surface form 一致 (固有名詞 / 略語) が外れる、UX が劣化
- 欠点: 実 RAG が hybrid を選ぶ理由を体感できない

### 4. pgvector / Faiss / OpenSearch を導入

- 利点: 本物の ANN search、production スタックに近い
- 欠点: **DB を Postgres に切り替える / 別ストアを立てる**必要 → 既存 3 プロジェクトの MySQL 統一が崩れる
- 欠点: 学習対象が「ベクタストア運用」にズレる。本 ADR の目的は "hybrid scoring の構造" であって "ANN ストアの選定" ではない
- 欠点: ローカル完結方針は満たすがスコープが膨らむ → **Terraform 側で OpenSearch を本番想定として描き、コードは MySQL + numpy で書く** という二段構え (youtube ADR 0001 の "Solid Queue × SQS" と同じ方針) を採る

### 5. 本物の sentence-transformers (all-MiniLM-L6 等) をローカルで実行

- 利点: 意味類似度が現実的に動く
- 欠点: モデルダウンロード (数百 MB) / Python 依存の肥大 / 起動時間が学習体験を悪化させる
- 欠点: 学習対象は "RAG の構造" であって "埋め込みモデルの精度" ではない
- → **派生 ADR で「mock encoder → real model」差し替え議論として扱える余地を残す**

### 6. Reciprocal Rank Fusion (RRF)

- 利点: 異なるスコアスケール統合の標準手法。重み調整の頭痛が減る
- 欠点: 初期実装としては weighted sum + min-max が読みやすい
- → 第二弾 ADR で RRF を導入する形に残す (まずは weighted sum で土台を作る)

## 採用理由

- **学習価値**: 「BM25 と cosine の min-max 正規化 → 重み付き和」という hybrid scoring の中核ロジックがコードに残る
- **アーキテクチャ妥当性**: 実 RAG (LangChain `EnsembleRetriever`, LlamaIndex `QueryFusionRetriever`) も BM25 + ベクタの hybrid が標準。スケールこそ違えど構造は同じ
- **責務分離**: BM25 (DB 側) / ベクタ (numpy 側) / 重み統合 (Python の純関数) が分離可能。各々独立に unit-test できる
- **将来の拡張性**: encoder 差し替え (擬似 → mini-LM)、weighted sum → RRF、in-memory → Faiss、いずれもこの ADR の前提を覆さずに進化できる

## 却下理由

- BM25 only / ベクタ only: hybrid 議論が学べず、差別化点が薄れる
- pgvector / Faiss / OpenSearch: スコープを越え、MySQL 統一が崩れる。本番想定として Terraform で扱う
- 本物の sentence-transformers: 学習対象がモデル運用にズレる
- RRF 初手採用: 重み付き和の方が初学者に読みやすく、改善の起点として残せる

## 引き受けるトレードオフ

- **意味類似度の精度は擬似 encoder の限界に縛られる (意図した制約)**: クエリ「東京の高層建築」と「東京タワー」の cosine 類似度は本物のモデルほど高くならない。デモ用 seed では surface form が一致するクエリを優先する。**精度ではなく構造とデータ運用を学ぶ**ことを ADR 冒頭で固定
- **退化ケース**: 擬似 encoder の cosine が機能しない場合、α=0.5 でも実質 BM25 only と同じランキングになり得る。これは **学習価値の毀損ではなく、α を 0 / 0.5 / 1 で切り替えるテストに使える** 性質と捉える (`test_score_fusion.py` で α 境界を assert)
- **コーパス全 chunk を numpy in-memory**: 数千件までは問題なし。1 万件超えたら Faiss や ANN ストアに切り替える必要 (本番 Terraform に OpenSearch を描く)
- **メモリ見積り**: 256-d float32 = 1024 byte / chunk。1 万 chunk で 10 MB。FastAPI を gunicorn の **複数 worker で起動すると fork 後にコピーオンライトで膨らむ** ので、Phase 2 では **uvicorn 単一プロセス** で動かす。本番想定は worker = 1 + thread pool で読みのみ並列化 (Terraform 上で記載)
- **コールドスタート**: ai-worker 起動時に embedding 全件を numpy にロードする時間がかかる (数千件なら数秒)。FastAPI の `lifespan` (startup hook) で実装する。`/health` は **ロード完了まで 503 を返す** ことで前段 LB / k8s readiness と整合
- **embedding 再生成は明示的トリガ**: 擬似 encoder のロジックを変えると全 chunk の embedding が変わる。`embedding_version` を chunks に持たせ、不一致なら `rake corpus:reembed` で再計算 (自動再計算はしない)
- **MySQL FULLTEXT の最小マッチ長**: ngram parser のデフォルト n=2、`innodb_ft_min_token_size=2` を my.cnf 経由で設定する必要がある (youtube と同じ手法)
- **FULLTEXT は `chunks` 側に張る (sources ではない)**: 検索の単位は chunk なので `chunks(body)` に FULLTEXT インデックスを置く。source タイトルでの絞り込みは Phase 2 で必要になれば別途検討するが、初期スコープでは `chunks.body` のみが retrieval 対象
- **正規化の再現性**: min-max 正規化はクエリごとに上限・下限が変わるので、**結果の絶対 score は比較できない**。同一クエリ内のランキングだけが意味を持つ

## このADRを守るテスト / 実装ポインタ（Phase 2 以降で実装）

- `perplexity/backend/db/migrate/*_create_sources.rb` — title / url / body
- `perplexity/backend/db/migrate/*_create_chunks.rb` — `body TEXT` + `FULLTEXT(body) WITH PARSER ngram` + `embedding BLOB` + `embedding_version` カラム
- `perplexity/backend/lib/tasks/corpus.rake` — `corpus:ingest` / `corpus:reembed` (再計算トリガ)
- `perplexity/backend/app/services/corpus_ingestor.rb` — chunk 分割 + ai-worker `/corpus/embed` 呼び出し + BLOB 書き込み (書き込みは Rails 一意化、ADR 0001 と整合)
- `perplexity/ai-worker/main.py` — `lifespan` で embedding 全件を numpy にロード (cold start)
- `perplexity/ai-worker/services/retriever.py` — BM25 (MySQL FULLTEXT) + cosine の hybrid 実装
- `perplexity/ai-worker/services/encoder.py` — 擬似 encoder (deterministic hash → 256-d float32) + `version()` 返却
- `perplexity/ai-worker/services/score_fusion.py` — min-max 正規化 + weighted sum (純関数で unit-test)
- `perplexity/ai-worker/tests/test_score_fusion.py` — 重み境界 (alpha=0 / 1) / 退化 (全件同点) / top-k cut
- `perplexity/ai-worker/tests/test_retriever_integration.py` — 既知 chunk が hybrid で上位に返ること
- `perplexity/ai-worker/tests/test_ai_worker_db_readonly.py` — ai-worker が INSERT / UPDATE を発行しないことを SQL ログで確認 (ADR 0001 の DB 権限規約)
- `perplexity/backend/spec/requests/queries_retrieve_spec.rb` — Rails が retrieve 結果を `query_retrievals` audit テーブルに保存していること
- `perplexity/backend/spec/services/corpus_ingestor_spec.rb` — embedding が JSON で受信され BLOB に正しく pack されること (byte 順検証)

## 関連 ADR

- ADR 0001: RAG パイプライン分割 (`/retrieve` の位置付け)
- ADR 0003: SSE streaming (retrieve は同期 HTTP、stream は synthesize ステージのみ)
- youtube ADR 0004: MySQL FULLTEXT (ngram) 採用 — 本 ADR の前段にあたる学習段
