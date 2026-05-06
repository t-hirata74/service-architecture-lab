# ADR 0003: 録画 finalize → ai-worker 要約 の at-least-once パイプライン

## ステータス

Accepted（2026-05-06）

## コンテキスト

Zoom 風プロジェクトの 3 つ目の中核技術課題は **「会議終了をトリガに、録画 finalize と要約生成を非同期で確実に走らせる」** こと。失敗時にリトライしても重複処理されない（=「会議 1 件 = 要約 1 件」）保証が必要になる。

制約:

- ローカル完結（録画ファイルそのものはモック、ai-worker の要約も deterministic な固定文字列 mock）
- shopify ADR 0004（外向き webhook 配信）とは違う技術課題に焦点を当てたい — あちらは **外向き** × **HMAC + delivery_id idempotency_key**、こちらは **内向き（Rails → ai-worker）** × **DB UNIQUE 制約による冪等保証** の対比軸を取る
- ai-worker は本リポ標準の「内部 trusted ingress（共有トークン）」で呼ぶ（perplexity / github / shopify と同じパターン）
- 「会議 1 件 = 要約 1 件」を **DB 制約レベルで保証**したい（アプリ層のロジックに依存しない）
- ジョブは at-least-once（少なくとも 1 回は実行されるが、重複しうる）前提で組む

## 決定

**`ended` 遷移時に `FinalizeRecordingJob` を enqueue → 完了後に `SummarizeMeetingJob` をチェイン → ai-worker `/summarize` を内部 ingress で呼ぶ。冪等は `summaries (meeting_id UNIQUE)` の DB 制約で吸収する** を採用する。

- enqueue は `enqueue_after_transaction_commit = true`（ADR 0001 と同じ）で状態 commit 後に発火
- `FinalizeRecordingJob`: 録画ファイル（モック）の finalize → `recordings` テーブルに 1 行作成 → `meeting.mark_recorded!`（`ended → recorded` 遷移）→ `SummarizeMeetingJob` を enqueue
- `SummarizeMeetingJob`: ai-worker `POST /summarize { meeting_id, recording_id, transcript_seed }` を内部 ingress 越しに呼ぶ → 結果を `summaries.upsert` （`meeting_id` UNIQUE で 2 回目以降は no-op）→ `meeting.mark_summarized!`
- ai-worker 側の `/summarize` は **入力ハッシュベースの deterministic mock**（同じ入力なら同じ要約文字列を返す）
- リトライ: Solid Queue の標準 retry policy（exponential backoff）に従う、最大 5 回失敗で `summarize_failed` 状態に落とし、ホスト操作で再開可能

## 検討した選択肢

### 1. 内部 ingress + `summaries (meeting_id UNIQUE)` 制約 ← 採用 (C3)

- shopify ADR 0004 が `webhook_deliveries (delivery_id UNIQUE)` で吸収していたのに対し、こちらは **結果保存テーブル自体の UNIQUE** で吸収
- 「冪等は idempotency_key テーブル」vs「冪等は結果テーブルの UNIQUE」の 2 軸対比が立つ
- 1 テーブル少なくて済む（idempotency_key 専用テーブル不要）

### 2. `summary_jobs (idempotency_key UNIQUE)` 専用テーブル + 結果は `summaries` 別管理

- shopify と完全同形
- 欠点: shopify との対比軸が弱くなる（同じパターンの reapply）
- 欠点: 1 テーブル余分。`summaries` 側に同じ制約を置けば済むのに二重管理になる

### 3. ai-worker 側で idempotency-key ヘッダ受け取り + ai-worker DB に状態保持

- ai-worker が完全に冪等になる（同じ key で 2 回叩かれても 1 回だけ計算）
- 欠点: ai-worker 側に DB（あるいは Redis）が必要になる。本リポの ai-worker は「stateless mock」方針なので破る
- 欠点: 結局 Rails 側の `summaries` 保存も冪等にしないと意味がない（多層になる）

### 4. SQS / Kafka 等の外部キュー

- 本番想定では検討に値する
- 欠点: ローカル完結方針に反する。shopify ADR 同様 **Terraform 側に SQS を描き、コードは Solid Queue** で割り切る

## 採用理由

- **学習価値**: 「冪等保証をどこに寄せるか」の選択肢を、shopify (idempotency_key テーブル) と zoom (結果テーブルの UNIQUE) で **同一リポ内で対比できる**。実プロダクトでも両方のパターンが採用される判断軸の素材になる
- **アーキテクチャ妥当性**: 内部 ingress + 結果テーブルの UNIQUE は、本リポでも perplexity / github の ai-worker 連携で踏んだパターンの正統な延長。さらに「結果が 1:1 対応する」ドメイン（会議 → 要約）では UNIQUE 制約に寄せるのが自然
- **責務分離**: ai-worker は stateless mock のまま、Rails 側だけが冪等を担保。境界が清潔
- **将来の拡張性**: `summaries.meeting_id UNIQUE` を `UNIQUE(meeting_id, version)` に拡張すれば「再要約バージョン管理」も同じ制約で表現できる

## 却下理由

- 専用 idempotency_key テーブル: shopify との対比軸が消える。学習価値が落ちる
- ai-worker 側冪等: stateless mock 方針を破る。多層冪等は MVP に過剰
- 外部キュー: ローカル完結方針違反

## 引き受けるトレードオフ

- **「同じ要約を 2 回計算してしまう」可能性は残る**: ai-worker は stateless で同じ入力で 2 回呼ばれうる。**計算結果は捨てるが計算コストは払う**ことになる。本リポの mock は計算量ゼロなので非問題、本物の LLM を使う本番では ai-worker 側にも cache 層を挟む設計に拡張する（本 ADR では扱わない）
- **`mark_summarized!` の遷移と `summaries.upsert` の競合**: `SummarizeMeetingJob` が 2 回走った場合、両方が `upsert` した後に両方が `mark_summarized!` を呼びうる。`mark_summarized!` 内の `with_lock`（ADR 0001）で「`recorded` 以外なら no-op」にすることで吸収する。**遷移失敗を例外にせず冪等に no-op** にするのが本 ADR の要請
- **失敗状態 `summarize_failed` からの再開操作**: ホスト UI に「再要約」ボタンを置く（実装は最小、`SummarizeMeetingJob.perform_later` を再呼び出しするだけ）。ADR 0001 で `*_failed → recorded` の戻り遷移を許容しているのでこれで完結する
- **shopify と「冪等保証の場所」が違うことの教育的負担**: 本リポを最初から読む人は「同じ at-least-once でもなぜ実装が違うのか」を `docs/operating-patterns.md` で読み比べる必要がある。本 ADR と shopify ADR 0004 の **両方からクロスリンク**して読み筋を作る

## このADRを守るテスト / 実装ポインタ

- `zoom/backend/db/migrate/*_create_summaries.rb` — `meeting_id` に `UNIQUE` 制約、`belongs_to :meeting`
- `zoom/backend/db/migrate/*_create_recordings.rb` — `meeting_id` に `UNIQUE` 制約（会議 1 件 = 録画 1 件）
- `zoom/backend/app/jobs/finalize_recording_job.rb` — `recordings.upsert` + `meeting.mark_recorded!` + `SummarizeMeetingJob` を enqueue
- `zoom/backend/app/jobs/summarize_meeting_job.rb` — `Internal::Client.summarize(...)` 呼び出し + `summaries.upsert` + `meeting.mark_summarized!`
- `zoom/backend/app/lib/internal/client.rb` — 内部 ingress（共有トークン Bearer、httpx）
- `zoom/ai-worker/app/routers/summarize.py` — deterministic mock（入力ハッシュ → 固定文字列 dictionary）
- `zoom/backend/spec/jobs/summarize_meeting_job_spec.rb` — 同じジョブを 2 回実行しても `summaries` が 1 件のままであること
- `zoom/backend/spec/jobs/finalize_recording_job_spec.rb` — `recordings` UNIQUE 違反は rescue して mark_recorded! へ進む
- `zoom/backend/spec/integration/recording_to_summary_pipeline_spec.rb` — `ended → recorded → summarized` の E2E（perform_enqueued_jobs ブロック内）

## 関連 ADR

- ADR 0001: 会議ライフサイクル状態機械 — 本パイプラインは ADR 0001 の状態遷移を後段で駆動する
- ADR 0002: ホスト権限 — `finalize_recording_job` の発火権限はホストのみ、Resolver 経由
- shopify ADR 0004（リポ内対比） — 「外向き webhook × idempotency_key テーブル」vs「内向き ingress × 結果テーブル UNIQUE」の対比軸
- youtube ADR 0001 — Solid Queue + `enqueue_after_transaction_commit` の前例
