# ADR 0001: 会議ライフサイクルの状態機械

## ステータス

Accepted（2026-05-06）

## コンテキスト

Zoom 風プロジェクトの中核技術課題は **「会議という長寿命エンティティの状態遷移を、参加者・ホスト・録画パイプラインが同時に触る前提で一貫して管理する」** こと。会議は分単位〜時間単位で生存し、その間に複数の actor（ホスト 1 / 共同ホスト N / 参加者 M / 後段の録画 finalize ジョブ）が並行して状態を進めようとする。

制約:

- ローカル完結（WebRTC SFU はモック扱い、policy で別領域として除外）
- youtube ADR 0001 とは違う技術課題に焦点を当てたい — あちらは「1 件のアップロード = 1 件のジョブ寿命」だが、こちらは **会議という長寿命エンティティ**（DB 上に分単位〜数時間 live 状態で残る）の状態管理が中心
- 状態遷移とビジネスデータ更新（参加者リスト、録画ファイル、ホスト移譲）を **同一トランザクションで commit したい**
- 「ホストが ended に遷移させる」と「最後の参加者退出で自動 ended に遷移させる」が並行発火するレースを正しく扱う必要がある

## 決定

**`meetings.status` を ENUM として永続化し、状態遷移はモデルメソッド + `with_lock` ブロック経由でしか行えなくする。録画 finalize / 要約は Solid Queue ジョブにチェインし、enqueue は `enqueue_after_transaction_commit = true` で状態 commit 後に発火する** を採用する。

- 取りうる状態: `scheduled → waiting_room → live → ended → recorded → summarized`
- 失敗系: `recording_failed`（録画 finalize 失敗）/ `summarize_failed`（ai-worker 要約失敗、リトライ可）
- 状態遷移は必ずモデルメソッド経由（`meeting.start!`, `meeting.end!`, `meeting.mark_recorded!`, `meeting.mark_summarized!` 等）で、内部で `with_lock` を張る
- ジョブは Active Job + Solid Queue（Rails 8 標準・MySQL 同居）
- 録画 finalize → 要約は **同一ジョブチェーン内**で連結し、各遷移を別トランザクションで commit（途中失敗は `*_failed` 状態で停止、再試行可能）

## 検討した選択肢

### 1. ENUM + `with_lock` + モデルメソッド + Solid Queue ← 採用

- 取りうる状態を DB の制約として強制（不正値が入らない）
- `with_lock` で「ホスト ended」と「自動 ended」のレースを直列化
- youtube ADR 0001 と同じく Rails 8 Solid トリオに統一、リポ内でのスタック一貫性
- 失敗系を別状態として残せるので「再開可能」が明示できる

### 2. `aasm` / `state_machines` gem

- DSL が綺麗で遷移定義が読みやすい
- 欠点: 並行制御は gem 側ではやってくれない（結局 `with_lock` を自前で重ねる必要があり、二重抽象になる）
- 欠点: 学習目的では「状態機械を gem に隠さず手で書く」方が DB 競合の挙動が理解できる

### 3. event sourcing（`meeting_events` 追記テーブル → 投影）

- 「誰がいつ何を遷移させたか」が完全に残り、監査に強い
- 欠点: Zoom 風 MVP の規模には過剰、ドメインの本筋（権限・録画パイプライン）から目が逸れる
- 欠点: youtube ADR の単純 ENUM との対比軸が弱くなる

## 採用理由

- **学習価値**: youtube は「ジョブ寿命 = エンティティ寿命」だったが、zoom は **エンティティが長寿命で複数 actor が触る** 設計を体験できる。`with_lock` の必要性が youtube より自然に出る
- **アーキテクチャ妥当性**: 実 Zoom も「会議 ID」単位で状態遷移を直列化していると推測できる（共同ホスト譲渡などは順序が重要）。MySQL の row lock + ENUM は素直な選択
- **責務分離**: 状態遷移は Rails モデル、録画 finalize の I/O はジョブ、要約は ai-worker にそれぞれ分離。controller には遷移ロジックを書かない
- **将来の拡張性**: 状態を増やす（`paused` で休憩、`scheduled_recurring` で定期会議 等）も ENUM に追加するだけ

## 却下理由

- `aasm`: 二重抽象。`with_lock` を結局書くなら DSL のメリットが薄い。学習目的にも反する
- event sourcing: スコープ外。MVP の学びの主軸を権限グラフと録画パイプラインに置きたいので、状態管理は最小コストにする

## 引き受けるトレードオフ

- **状態数の増加圧力**: 「録画開始 / 録画一時停止 / 自動延長 / breakout 中」など Zoom 実物の状態をすべて再現するとすぐ ENUM が膨らむ。本 ADR では「ライフサイクルの背骨だけ」を扱い、breakout / pause は **本 ADR では扱わない**（必要なら後続 ADR で別軸として追加）
- **`with_lock` のスループット**: 1 会議に同時に数百〜数千参加者が入る本番想定では行ロック直列化がボトルネックになる。学習用途では非問題、本番化するなら participants は別行で管理し、`meetings` 行は ended 遷移時のみ取る設計に分解する
- **失敗状態の分岐爆発**: `*_failed` を 1 つずつ作ると状態数が膨らむ。本 ADR では `recording_failed` と `summarize_failed` の **2 つに限定** し、それ以外の失敗（live 中の DB エラー等）はリトライ可能な遷移失敗として扱う（状態は据え置き）

## このADRを守るテスト / 実装ポインタ

- `zoom/backend/app/models/meeting.rb` — `status` ENUM 定義と遷移メソッド (`start!`, `end!`, `mark_recorded!`, `mark_summarized!`)
- `zoom/backend/app/models/meeting.rb` — 各遷移メソッド内の `with_lock` ブロック
- `zoom/backend/app/jobs/finalize_recording_job.rb` — `ended → recorded` を駆動、失敗時 `recording_failed`
- `zoom/backend/app/jobs/summarize_meeting_job.rb` — `recorded → summarized`、失敗時 `summarize_failed`、ai-worker タイムアウトでリトライ
- `zoom/backend/app/jobs/application_job.rb` — `self.enqueue_after_transaction_commit = true`
- `zoom/backend/spec/models/meeting_state_machine_spec.rb` — 不正遷移は `InvalidTransition`、`with_lock` 並行 spec（2 thread で同時 end! を呼んで 1 つだけ成功する）
- `zoom/backend/spec/jobs/finalize_recording_job_spec.rb` — 失敗時 `recording_failed` で停止、retry で `recorded` に進む
- `zoom/playwright/tests/meeting_lifecycle.spec.ts` — scheduled → live → ended → recorded → summarized を E2E

## 関連 ADR

- ADR 0002（予定）: ホスト / 共同ホスト / 参加者の権限モデル — 状態遷移の **発火権限**（誰が `end!` を呼べるか）はこちらに分離
- ADR 0003（予定）: 録画 finalize → ai-worker 要約 の at-least-once パイプライン — `recorded → summarized` 遷移の冪等保証はこちらに分離
- youtube ADR 0001 — 状態機械の対比軸（ジョブ寿命 vs エンティティ寿命）
