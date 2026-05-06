# ADR 0002: ホスト / 共同ホスト権限と動的譲渡

## ステータス

Accepted（2026-05-06）

## コンテキスト

Zoom 風プロジェクトの 2 つ目の中核技術課題は **「会議の最中にリアルタイムで動く権限グラフ」** をどう DB に表現するか。Zoom 実物では以下が live 中に発生する:

- ホストが共同ホスト (co-host) を指名 / 取消
- ホストが先に退出するとき、ホスト権限そのものを別人に **譲渡**（`host_id` が別人になる）
- ホストや共同ホストが参加者を強制ミュート / 強制退出（権限の **行使**）
- ホストが「待機室から入室許可」を出す（権限の **発動**）

制約:

- ローカル完結
- github ADR の権限モデル（Org/Team/Collaborator の **静的** 継承グラフ）とは違う技術課題に焦点を当てたい — こちらは **動的（live 中に状態が動く）** + **監査必須**（誰が誰を譲渡したか / 強制ミュートしたかが履歴に残る必要がある）
- 譲渡レース（A が B に譲渡しようとした瞬間に B が退出する）を正しく扱う必要がある
- 「最大 1 ホスト」の不変条件を DB 制約で表現したい（アプリ層の競合で 0 人 / 2 人ホストが発生するのを防ぎたい）

## 決定

**`meetings.host_id` を本体カラム + `meeting_co_hosts` 中間テーブル + `host_transfers` 追記テーブルの 3 つで表現する** を採用する。

- `meetings.host_id`: 現在のホスト（`NOT NULL`、最大 1 人を物理的に保証）
- `meeting_co_hosts (meeting_id, user_id)`: 共同ホスト N 件、`UNIQUE(meeting_id, user_id)`
- `host_transfers (meeting_id, from_user_id, to_user_id, transferred_at, reason)`: ホスト譲渡履歴（追記のみ、UPDATE / DELETE しない）
- 譲渡操作は `Meeting#transfer_host_to!(new_host)` メソッドに集約し、内部で `with_lock` を張った上で `host_id` 更新と `host_transfers` insert を **同一トランザクション**で commit
- 権限判定は `MeetingPermissionResolver`（PORO）に集約 — github ADR と同じ命名規約に揃える
- Pundit policy はこの Resolver を呼ぶだけの薄い層に留める（github と同じ 2 層構造）

## 検討した選択肢

### 1. `host_id` + `co_hosts` 中間 + `host_transfers` 履歴（B3）← 採用

- 「最大 1 ホスト」を `host_id NOT NULL` で物理保証（複合制約不要）
- 譲渡履歴が独立テーブルなので「いつ誰から誰へ」が完全に残る
- 監査クエリ（過去 30 日でホスト譲渡が何件あったか）が直接書ける
- github ADR の `PermissionResolver` 構造を踏襲しつつ、「履歴」軸で差別化できる

### 2. `meeting_grants(meeting_id, user_id, role)` 単一テーブル

- 一覧クエリは綺麗（`SELECT role FROM meeting_grants WHERE meeting_id = ?`）
- 欠点: 「最大 1 host」を DB 制約で保つには **MySQL では generated column + UNIQUE トリック**が必要（`role = 'host'` のときだけ `meeting_id` を入れる generated column に UNIQUE）。テーブル設計が学習主旨から逸れる
- 欠点: 譲渡履歴が「同じ行の UPDATE」になり追跡しづらい

### 3. event sourcing（`meeting_permission_events` から都度投影）

- 監査は完全
- 欠点: 権限判定のたびに event 集計が要り、N+1 / コスト過剰
- 欠点: ADR 0001 で event sourcing を却下した方針と整合

## 採用理由

- **学習価値**: 「動的権限 + 監査履歴」を DB に落とすと **本体テーブル / 中間テーブル / 履歴テーブル** の 3 種に分解する典型解になる。github の静的継承と並べると「権限設計の 2 軸」が学べる
- **アーキテクチャ妥当性**: 実 Zoom も「現状ホスト 1 人 + 過去譲渡履歴」を別レイヤーで持っていると推測できる（live クエリと監査クエリの読み筋が違う）
- **責務分離**: 権限判定は `MeetingPermissionResolver` に集約、controller は判定結果しか見ない。ADR 0001 の状態遷移メソッドは「権限あり前提」で動き、権限チェックは Pundit の前段に置く
- **将来の拡張性**: `meeting_co_hosts` に `granted_by_user_id` / `granted_at` カラムを追加すれば「指名履歴」も同形で追える。本 ADR ではホスト譲渡履歴のみ扱うが拡張は容易

## 却下理由

- 単一 `meeting_grants` テーブル: 「最大 1 host」の DB 制約が generated column trick になり、設計が学習主旨から逸れる。譲渡履歴の表現も歪む
- event sourcing: ADR 0001 と整合。MVP の規模で投影コストを払う価値が無い

## 引き受けるトレードオフ

- **3 テーブル分散**: 1 つの「権限スナップショット」を取るのに 2 テーブル JOIN（`meetings` + `meeting_co_hosts`）が必要。学習用途では問題なし、巨大スケールでは Redis 等のキャッシュで吸収する設計に分解する想定（本 ADR では扱わない）
- **譲渡履歴の追記専用**: `host_transfers` は **絶対に UPDATE / DELETE しない**。誤操作の取消は「逆譲渡を追記」で表現する（git log の revert と同じ哲学）。アプリ層に「履歴を消すコード」が無いことを spec で固定する
- **譲渡レースの一部は失敗**: A が B に譲渡しようとした瞬間に B が退出した場合、`with_lock` で直列化されているので「B 退出を先に処理 → 譲渡は `to_user_id` が participant でない、として失敗」になる。アプリは譲渡失敗を素直にエラーにし、ホスト側で再試行（別人選択）を求める。**譲渡時点での participant 在席を DB 制約では表現しない**（アプリ層の `with_lock` 内チェックで吸収）
- **強制ミュート / 強制退出の権限行使ログ**: 本 ADR では扱わない（必要なら別 ADR で `permission_actions` 追記テーブルを追加）。今回は「ホスト譲渡」だけが履歴対象

## このADRを守るテスト / 実装ポインタ

- `zoom/backend/db/migrate/*_create_meetings.rb` — `host_id NOT NULL`、`belongs_to :host, class_name: 'User'`
- `zoom/backend/db/migrate/*_create_meeting_co_hosts.rb` — `UNIQUE(meeting_id, user_id)`
- `zoom/backend/db/migrate/*_create_host_transfers.rb` — 追記専用、`from_user_id` / `to_user_id` / `transferred_at`
- `zoom/backend/app/models/meeting.rb` — `transfer_host_to!(new_host)` メソッドで `with_lock` + 履歴 insert
- `zoom/backend/app/services/meeting_permission_resolver.rb` — `can_end?(user)`, `can_admit_from_waiting_room?(user)`, `can_force_mute?(user, target)` 等
- `zoom/backend/app/policies/meeting_policy.rb` — Resolver を呼ぶだけの薄い Pundit policy
- `zoom/backend/spec/models/meeting_host_transfer_spec.rb` — 譲渡レース（並行 thread spec）/ 譲渡で退出済 user に渡そうとした失敗ケース
- `zoom/backend/spec/services/meeting_permission_resolver_spec.rb` — host / co-host / participant それぞれの判定行列
- `zoom/backend/spec/models/host_transfer_immutability_spec.rb` — `host_transfers` への UPDATE / DELETE がアプリコード上どこにも無いことを fixate

## 関連 ADR

- ADR 0001: 会議ライフサイクル状態機械 — 状態遷移の **発火可否**は本 ADR の Resolver で判定
- ADR 0003（予定）: 録画 finalize → ai-worker 要約パイプライン — `finalize_recording_job` の発火権限はホストのみ、判定は本 ADR の Resolver 経由
- github `0001-permission-graph.md`（リポ内対比） — 静的継承との対比軸
