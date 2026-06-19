# ADR 0002: 複式簿記の不変条件 — append-only 仕訳 ledger + 借方=貸方 を deferred constraint trigger で強制

## ステータス

Accepted（2026-06-19）

## コンテキスト

複式簿記の核心は **1 つの仕訳（journal entry）の借方合計 = 貸方合計** という不変条件。これが崩れた仕訳は会計的に無意味で、試算表・貸借対照表が壊れる。本プロジェクトはこの invariant を「どこで保証するか」を主題にする。

会計ドメイン特有の制約：

- 不変条件は **複数行（journal_lines）にまたがる集計** （`SUM(debit) = SUM(credit)`）。単一行の `CHECK` 制約では表現できない。
- **記帳済み仕訳は後から書き換えない**（append-only）。会計の大原則「訂正は逆仕訳で表す」を再現する。残高は仕訳の積み上げで決まり、過去を改竄すると監査可能性が失われる。
- 金額は浮動小数点では扱わない（丸め誤差で借方≠貸方が起きる）。
- 本リポ初の Postgres。MySQL に無い **DEFERRABLE 制約 / CONSTRAINT TRIGGER** を使い「トランザクション末で集計検証する」Postgres 固有の道具を学ぶ。

## 決定

**header/lines 2 テーブル + `NUMERIC` 金額 + 借方=貸方 を DEFERRABLE INITIALLY DEFERRED な constraint trigger で COMMIT 時に強制 + 記帳済みは append-only（訂正は逆仕訳）** を採用する。

- `journal_entries`（header: `company_id`, `entry_date`, `description`, `reversed_entry_id` nullable）
- `journal_lines`（`company_id`, `journal_entry_id`, `account_id`, `side` ENUM(`debit`/`credit`), `amount NUMERIC(18,2) CHECK (amount > 0)`）
- 借方=貸方は **`CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED`** で実装。明細を 1 行ずつ INSERT する途中では不均衡を許し、**COMMIT 時に entry 単位で `SUM(debit) = SUM(credit)` を検証**して違反なら abort する
- アプリ層（Hono + Drizzle）でも記帳前に同じ検証を行い、**ユーザー向けの 422 エラーメッセージ**を返す（DB trigger は最終防衛線、UX はアプリ層）
- **append-only**: 記帳済み `journal_entries` / `journal_lines` への UPDATE / DELETE を trigger で物理拒否（または実行時ロールから `UPDATE/DELETE` 権限を REVOKE）。訂正は元仕訳を指す `reversed_entry_id` を持つ**逆仕訳（借方貸方を入れ替えた新規 entry）を記帳**して表す

## 検討した選択肢

### 借方=貸方 の強制場所

#### 1. DEFERRABLE constraint trigger（DB 強制・COMMIT 時集計）＋ アプリ層プリチェック ← 採用

- 利点: 明細を順に INSERT できる（途中の不均衡を許す）うえ、**DB が最終的に必ず均衡を保証**。Postgres の deferred 制約という固有機能の学習
- 利点: アプリ層プリチェックで親切なエラー、trigger で防衛線、の二段
- 欠点: trigger の PL/pgSQL を書く必要がある

#### 2. アプリ層のトランザクション内検証のみ

- 利点: 実装が単純、SQL に閉じない
- 欠点: DB が保証しないので、別経路（バッチ / 手 SQL）からの不均衡を防げない。RLS で「DB で締める」方針（ADR 0001）と一貫しない

#### 3. 行レベル `CHECK` / 非正規化合計カラム + `CHECK(debit_total = credit_total)`

- 利点: 制約が宣言的
- 欠点: 行 `CHECK` は兄弟行を集計できない。非正規化合計はトリガ保守が必要で、結局 trigger を書くなら集計検証 trigger のほうが正直

### 訂正の表し方

- **逆仕訳（採用）**: 元仕訳は不変、逆仕訳で打ち消し、必要なら正しい仕訳を再記帳。監査証跡が残る
- UPDATE で直接修正（却下）: append-only 原則・監査可能性に反する

## 採用理由

- **学習価値**: 「集計不変条件を DB の deferred 制約で守る」という、行 `CHECK` では届かない領域を Postgres 固有機能で学べる。append-only + 逆仕訳は shopify の StockMovement ledger / zoom の HostTransfer と同じ **append-only 監査の系譜**で、金額ドメインに写したもの
- **アーキテクチャ妥当性**: 実会計システムは例外なく append-only ledger + 逆仕訳。借方=貸方を DB 不変条件にするのは堅牢設計の定番
- **責務分離**: 不変条件は DB（最終防衛線）、UX エラーはアプリ層、と層を分ける
- **将来の拡張性**: 補助元帳 / 部門軸の追加は line に列を足すだけ。残高は仕訳の projection なので集計テーブルは後から非正規化可能

## 却下理由

- アプリ層のみ: DB が保証せず、ADR 0001 の「DB で締める」思想と不一致
- 行 CHECK / 非正規化合計: 兄弟行集計ができない / 結局 trigger 保守が要る
- UPDATE 修正: append-only・監査可能性に反する

## 引き受けるトレードオフ

- **constraint trigger の複雑さ**: PL/pgSQL を書く。ロジックは「entry 単位の SUM 比較」1 つに閉じ込め、テストで固定する
- **逆仕訳の冗長性**: 訂正のたびにレコードが増える。これは監査証跡として意図的に受け入れる
- **NUMERIC の取り回し**: Drizzle / Hono RPC 境界で文字列⇄数値の変換が要る（JS の number は金額に使わない）。境界変換規約を ADR 0004 で扱う
- **多通貨は scope 外**: 単一通貨前提。多通貨は為替差損益という別の不変条件論点になるので別 ADR に切る

## このADRを守るテスト / 実装ポインタ

- `backend/test/domain.test.ts` — balanced 記帳 201 / 借方≠貸方 400 (zod refine) / 逆仕訳で借方貸方反転
- `backend/scripts/smoke.ts` — DB 層で「借方≠貸方を COMMIT 時に拒否」「記帳済みの UPDATE を append-only trigger が拒否」
- `backend/src/domain/journals.ts` — 期間 open 事前チェック + `SET CONSTRAINTS ALL IMMEDIATE` で deferred trigger を同期発火 + 逆仕訳
- `backend/drizzle/0000_init.sql` — `freee_check_entry_balanced` (DEFERRABLE INITIALLY DEFERRED) / `freee_forbid_mutation` (append-only)

## 関連 ADR

- ADR 0001: RLS（仕訳・明細も `company_id` スコープ）
- ADR 0003: 期末締め（締め済み期間への記帳ガードは本 ADR の append-only と接続する）
- ADR 0004: Drizzle transaction / Hono RPC の NUMERIC 境界変換
- shopify ADR 0003 / zoom ADR 0002: append-only ledger・監査テーブルの先行事例
