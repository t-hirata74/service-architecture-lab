# ADR 0003: 期末締め state machine と締め済み期間への記帳ガード

## ステータス

Accepted（2026-06-19）

## コンテキスト

会計は期間（会計期間 / 月次）で区切り、**締め（close）た期間には記帳できない** ことを保証する必要がある。締め後に過去へ記帳できると、確定済みの試算表・決算が後から動いてしまう。

ドメイン制約：

- 期間は `open → closed` の状態を持つ。締めは不可逆が基本だが、本リポでは学習として **`reopen`（closed → open）** も状態遷移として扱い、state machine の戻り遷移を再現する（実務でも月次の修正で再オープンは起こる）。
- 記帳（ADR 0002 の仕訳作成）は **対象の `entry_date` が属する期間が `open` のときだけ**許す。締め済み期間への記帳・逆仕訳は拒否する。
- 期間は **company 内で重複してはならない**（同じ日が 2 つの期間に属さない）。本リポ初の Postgres なので、calendly が MySQL で `EXCLUDE` 制約の代替に苦労した論点を、ここでは **Postgres ネイティブの `EXCLUDE` 制約**で素直に解ける。
- 期間も tenant-scoped（ADR 0001 の RLS 対象）。

## 決定

**`accounting_periods`（`status` ENUM open/closed）+ 状態遷移を明示マップで管理 + 記帳時に対象期間が open かを検証 + 期間の非重複を Postgres `EXCLUDE` 制約で DB 強制** を採用する。

- `accounting_periods`（`company_id`, `name`, `starts_on`, `ends_on`, `status` ENUM(`open`/`closed`)）
- 状態遷移は `open → closed`（close）、`closed → open`（reopen）の 2 方向のみをアプリの遷移マップで許可。未定義遷移は弾く（zoom ADR 0001 の TRANSITIONS マップと同型）
- **記帳ガード**: 仕訳の `entry_date` から期間を引き、`status = 'open'` でなければ 409/422。アプリ層で検証しつつ、最終防衛線として `journal_lines` INSERT 時の constraint trigger でも「対象期間が closed なら abort」を強制（ADR 0002 の append-only trigger と同じ層）
- **非重複**: `EXCLUDE USING gist (company_id WITH =, daterange(starts_on, ends_on, '[]') WITH &&)` で、同一 company 内の期間が日付範囲で重ならないことを DB で保証（`btree_gist` 拡張を有効化）
- 締め操作自体は append-only な監査として `period_closings`（誰が・いつ締めた/再オープンした）に記録（zoom HostTransfer と同系）

## 検討した選択肢

### 締め済み期間への記帳ガードの置き場所

#### 1. アプリ層検証 + DB constraint trigger の二段 ← 採用

- 利点: アプリ層で親切なエラー、trigger で最終防衛線。ADR 0001/0002 の「DB で締める」方針と一貫
- 欠点: trigger と app の二重ロジック（ロジックは「期間 status 参照」1 つで小さい）

#### 2. アプリ層のみ

- 利点: 単純
- 欠点: バッチ / 手 SQL からの締め後記帳を防げない

### 期間の非重複制約

#### 1. Postgres `EXCLUDE` 制約 ← 採用

- 利点: 重複を DB が宣言的に拒否。calendly（MySQL）が代替に苦労した論点を Postgres ネイティブで解け、両者の対比が学習になる
- 欠点: `btree_gist` 拡張が要る（ローカルなら `CREATE EXTENSION` で済む）

#### 2. アプリ層で重複チェック

- 欠点: 並行作成でレースが起きる（calendly ADR が論じた通り）。DB 制約のほうが堅い

### reopen を許すか

- **許す（採用）**: state machine の戻り遷移を学習対象にできる。監査に再オープン理由を残す
- 不可逆（却下）: 単純だが state machine としての学びが薄い。実務でも月次再オープンは起きる

## 採用理由

- **学習価値**: 長寿命でない「期間」という軽い state machine + 戻り遷移 + 「締め」という業務イベントの監査。zoom（長寿命 meeting の state machine）との対比で「短い状態 + 強い不変条件」を学ぶ。`EXCLUDE` は calendly との Postgres/MySQL 対比
- **アーキテクチャ妥当性**: 期末締めはどの会計システムにもある。締め後記帳の拒否を DB まで落とすのは堅牢設計
- **責務分離**: 期間状態は `accounting_periods`、記帳ガードは仕訳作成フローと trigger、締め監査は `period_closings` に分離
- **将来の拡張性**: 年次決算 / 部門別締め / ロック粒度の細分化は期間モデルの拡張で対応できる

## 却下理由

- アプリ層のみのガード: DB が保証せず ADR 0001/0002 と不一致
- アプリ層重複チェック: 並行レース。`EXCLUDE` のほうが堅い
- 不可逆な締め: state machine の学習価値が薄い

## 引き受けるトレードオフ

- **二重ロジック**: 記帳ガードがアプリと trigger に重複。ロジックは「期間 status 参照」のみに限定し spec で固定
- **`btree_gist` 依存**: 拡張を有効化する初期化が増える。Postgres 固有機能の学習コストとして許容
- **reopen の整合**: 再オープン中に記帳 → 再締め、の間の試算表が動く。これは意図的に許容し、締め監査ログで追跡可能にする
- **期間粒度**: 月次/年次の同時管理は scope 外。MVP は単一粒度の期間列で表現

## このADRを守るテスト / 実装ポインタ（実装後に埋める）

- `backend/test/period/posting_guard.test.ts`（予定）— closed 期間への記帳・逆仕訳が拒否されること（アプリ層バイパス時も trigger で落ちる）
- `backend/test/period/no_overlap.test.ts`（予定）— 同一 company で重なる期間を作れないこと（`EXCLUDE` 違反）
- `backend/test/period/transitions.test.ts`（予定）— 未定義遷移を弾き、close / reopen のみ通ること
- `backend/drizzle/`（予定）— `accounting_periods` の `EXCLUDE` 制約、記帳ガード trigger、`period_closings` 監査テーブル

## 関連 ADR

- ADR 0001: RLS（期間も company スコープ）
- ADR 0002: append-only ledger（締め後記帳拒否は append-only ガードと同じ trigger 層）
- calendly ADR（期間 overlap / MySQL `EXCLUDE` 代替）: 本 ADR の Postgres ネイティブ対比対象
- zoom ADR 0001（meeting lifecycle state machine）: 状態遷移マップの先行事例
