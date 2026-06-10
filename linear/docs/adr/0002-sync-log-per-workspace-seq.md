# ADR 0002: per-workspace seq の sync log — counter 行 FOR UPDATE 採番で gapless 全順序

## ステータス

Accepted（2026-06-10）

## コンテキスト

sync engine の真実は「全 mutation の順序付き log」である。client は `lastSyncId` までを適用済みであることだけを覚え、`since=lastSyncId` の差分で必ず追いつけなければならない。要件:

- **全順序**: workspace 内の全 op に単調増加の `seq` が付く
- **gapless 読み取り**: `delta(since=N)` が「commit 済みの N より大きい op すべて」を返し、**後から N 以下や読み飛ばした op が出現しない**こと
- **初期ロードの速さ**: bootstrap は log replay でなく materialized snapshot から返す (figma ADR 0002 と同じ二層)

最大の罠は **AUTO_INCREMENT 採番**。MySQL の AUTO_INCREMENT は INSERT 時に採番されるが、**commit 順とは無関係**。txn A が id=5 を取り、txn B が id=6 を取って先に commit した場合、delta 読者は 6 を読んで `lastSyncId=6` とする。その後 A が commit しても、次回 `since=6` の読者は **id=5 を永遠に読み飛ばす**。これが sync engine 設計の核心の学習ポイント。

制約: ローカル完結 (MySQL 8 のみ)。Prisma interactive transaction を使う (ADR 0001)。

## 決定

**`workspaces.sync_seq` カウンタ行を `SELECT ... FOR UPDATE` でロックして採番し、同一トランザクションで sync_ops を INSERT する**。ロックは COMMIT まで保持されるため、workspace 内では **commit 順 = seq 順** が構造的に保証され、gap が原理的に発生しない。

- 採番単位は **workspace** (= WS room / 認可境界と一致)。1 mutation が N ops を生む場合は連続 seq を一括採番
- `sync_ops` は append-only。`UNIQUE(workspace_id, seq)`
- `delta(since=N)`: `WHERE workspace_id=? AND seq > N ORDER BY seq` — 上記保証によりこれだけで正しい
- `mutations` 台帳 (`client_mutation_id` UNIQUE) も同一 txn に乗せ、at-least-once 再送を冪等化 (ADR 0003)
- 適用順: `workspace 行 FOR UPDATE → seq 確定 → ドメイン更新 + ops INSERT + 台帳 INSERT → COMMIT → broadcast (ADR 0005)`

## 検討した選択肢

### 1. counter 行 + FOR UPDATE 採番 ← 採用

- commit 順 = seq 順を DB のロック機構だけで保証。アプリの実行形態 (プロセス数) に依存しない
- figma `documents.version` の `with_lock` 採番、shopify `Order#number` カウンタと同じ、本リポで実証済みのパターンの TS / Prisma 版

### 2. sync_ops.id の AUTO_INCREMENT をそのまま seq にする

- 実装最小。追加ロックなし
- 欠点: 上記のとおり id 順 ≠ commit 順で **読み飛ばしが起きる**。回避には「全 txn の最小 active id より下だけ読む」watermark が要るが、MySQL では active txn の採番状況を安価に取れず複雑化する。却下

### 3. アプリ内 async mutex で mutation を直列化 (single Node instance 前提)

- Node の単一イベントループに promise queue を置けば DB ロックなしで直列化できる
- 欠点: プロセスを 2 つ立てた瞬間に壊れる暗黙の前提を持ち込む。DB に不変条件を置く本リポの流儀 (shopify 条件付き UPDATE / calendly 制約ガード) にも反する

### 4. 採番テーブルを txn 外で先取りし、commit 後に「公開済み watermark」を別途進める

- 採番ロックの保持時間を短くできる
- 欠点: watermark 管理という第二の整合性問題が生まれ、MVP の複雑度に見合わない

## 採用理由

- **学習価値**: 「AUTO_INCREMENT は commit 順を保証しない」という、sync log / outbox / CDC 設計すべてに通じる罠を、対策込みで手で書ける
- **アーキテクチャ妥当性**: counter + 行ロックによる順序保証は Linear 系 sync engine やイベント outbox の実装で実際に使われる定石
- **責務分離**: 順序の不変条件が `sync` module の採番 1 箇所に集約され、ドメイン側は意識しない
- **将来の拡張性**: スケール時は workspace 単位 shard へ自然に分割できる (採番境界 = 配信境界 = 認可境界)

## 却下理由

- 案 2: gap 読み飛ばしという正しさの欠陥。本 ADR の存在理由そのもの
- 案 3: プロセス数 1 という暗黙前提が壊れやすく、DB 不変条件主義に反する
- 案 4: watermark の複雑度が MVP の学習価値を超える

## 引き受けるトレードオフ

- **workspace 内の書き込み直列化**: 同一 workspace への並行 mutation は counter 行ロックで待ち合う。MVP の同時編集人数では問題なく、これは「順序保証の対価」として意図的に払う (figma の document lock と同じ判断)
- **Prisma に row lock API がない**: 採番は `$queryRaw('SELECT ... FOR UPDATE')` の生 SQL になる。採番 1 箇所に限定して許容 (ADR 0001)
- **log の肥大**: sync_ops は無限追記。MVP では放置し、snapshot checkpoint + 古い op の truncate は派生論点として将来 ADR に切り出す

## このADRを守るテスト / 実装ポインタ

- `linear/backend/test/sync-gapless.e2e-spec.ts` — 並行 30 mutation を流しつつ delta を読み続け、「観測した seq 列に欠番がない / 重複しない」ことを検証する不変条件テスト (Phase 3 で実装・pass)
- `linear/backend/src/sync/sync.service.ts` — `lockSyncSeq` (FOR UPDATE) + `appendOps` + `bootstrap`/`delta` ($transaction 一括読みで torn snapshot 防止)。採番が単一サービスに閉じている
- `linear/backend/prisma/schema.prisma` — `UNIQUE(workspace_id, seq)` / `client_mutation_id UNIQUE`

## 関連 ADR

- ADR 0003: client 側の lastSyncId 管理と replay (この log を前提にする)
- ADR 0005: broadcast は COMMIT 後のヒント。真実は本 log で、取りこぼしは delta で自己修復
- figma ADR 0002: op log + materialized の二層 (同思想)。あちらは収束に Lamport clock が要るが、本プロジェクトは server 全順序なので seq のみで足りる — この差自体が学習対象
