# ADR 0003: client 同期戦略 — optimistic queue + rebase + offline replay

## ステータス

Accepted（2026-06-10）

## コンテキスト

ADR 0002 で server 側の真実 (全順序 sync log) が決まった。本 ADR は client 側、すなわち「Linear の体感」を作る部分を扱う。要件:

- **即時反応**: mutation は server 応答を待たず UI に反映する (optimistic update)
- **収束**: server が拒否したら巻き戻し、他者の変更とは server の op 順で必ず一致する
- **offline 耐性**: 切断中の編集を失わず、復帰時に自動送信する。リロードしても消えない
- **local-first の読み取り**: 一覧・検索・フィルタは server 往復なしでローカルキャッシュに当てる

figma の frontend は「client LWW + reconcile」だったが、あちらは収束ロジック (LWW) が client にもある。本プロジェクトは server 全順序が真実なので、client は「**確定済み状態 + 未確定 mutation の列**」という別の形を学ぶ。

## 決定

**confirmed state (server op 適用済み) と pending queue (未確定 mutation) を分離し、表示は `confirmed + pending の再適用` で導出する**。

- **永続化**: IndexedDB に per-workspace で `entities` (confirmed) / `meta.lastSyncId` / `pendingMutations` の 3 store。リロード・オフライン起動はここから復元
- **表示状態**: in-memory store が `confirmed` に `pending` を順に適用した派生 state を保持し、React へは `useSyncExternalStore` で公開 (coding-rules/frontend.md の既存パターン)。mutation の適用関数 (reducer) は `shared/` に置き、BE の適用結果と意味を揃える (ADR 0004)
- **mutation 発行**: `clientMutationId` (UUID) を採番 → pending に積む (IndexedDB 永続) → 楽観適用 → `POST /mutations`
- **confirm**: WS / delta で届いた op の `client_mutation_id` が pending と一致したら、その op を confirmed に適用し pending から除去。他者の op は confirmed に適用 → pending を再適用 (**rebase**)
- **拒否 (4xx)**: 該当 pending を破棄して再導出 (= 自動 rollback)。ユーザーへ toast 通知
- **offline 復帰**: ①delta catch-up → ②pending rebase → ③pending を順に再送。再送は at-least-once で、server の `client_mutation_id` UNIQUE 台帳が重複を no-op にする (ADR 0002)
- **競合解決**: server 順で last-write-wins (field 単位の merge はしない)。pending と矛盾する他者変更は rebase の適用順で解決される

## 検討した選択肢

### 1. confirmed + pending queue 分離 (rebase 方式) ← 採用

- rollback が「pending から消して再導出」に統一され、逆操作 (undo op) の生成が不要
- offline queue・再送・confirm が同じデータ構造で表現できる

### 2. 単一 state を直接書き換え + 失敗時に逆操作で巻き戻し

- 実装が直感的で適用コストが低い
- 欠点: mutation ごとに正確な逆操作を作る必要があり、他者 op が間に挟まると逆操作が壊れる (巻き戻し先が既に変わっている)。収束バグの温床

### 3. 楽観更新をしない (server 応答待ち + 全面 refetch)

- 最も単純で必ず正しい
- 欠点: 体感が通常の CRUD アプリになり、「Linear の体感を作る」という本プロジェクトの題材そのものを放棄する

### 4. TanStack Query の optimistic update 機構に乗せる

- 実務で頻出のライブラリで楽observability も良い
- 欠点: query 単位の cache 無効化モデルは「op log を順に適用する」sync engine と相性が悪く、lastSyncId の連続性管理を結局自前で書く。キャッシュの真実が二重化する

## 採用理由

- **学習価値**: optimistic UI の正攻法 (confirmed/pending 分離) を、永続 queue・冪等再送・rebase まで含めて一式実装する。Linear・Figma 等の local-first 系が共通で持つ構造
- **アーキテクチャ妥当性**: 「server 確定値と楽観値を混ぜない」は offline-first 設計の定石。Mutation queue + idempotency key は API 設計としても実務頻出
- **責務分離**: 収束の正しさは server (op 順) が持ち、client は「適用と再適用」だけを持つ。figma (client にも LWW) との対比が明確
- **将来の拡張性**: undo/redo は pending queue の上に自然に足せる。複数 tab は IndexedDB + BroadcastChannel へ発展可能 (scope 外)

## 却下理由

- 案 2: 逆操作方式は他者 op との交錯で壊れる。正しさを構造で守れない
- 案 3: 題材の放棄
- 案 4: sync log モデルと cache 無効化モデルの不整合。学習の主役を外部ライブラリに隠される

## 引き受けるトレードオフ

- **再適用コスト**: 他者 op 受信のたびに pending を再適用する。pending は通常数件で、entity 単位の適用は O(pending 数)。MVP 規模では無視できる
- **field merge はしない**: 同一 issue の title を双方が編集したら後勝ち。figma のような per-prop 収束はやらない (それは figma で学習済み。こちらは「server 順 LWW で十分」という製品判断ごと学ぶ)
- **IndexedDB の複雑さ**: localStorage に比べ API が重い。idb (薄い Promise wrapper) を使う前提 (依存はユーザー確認済みの枠内)

## このADRを守るテスト / 実装ポインタ

- `linear/client/src/sync-engine.ts` — confirmed + pending 分離の SyncEngine 本体 (framework 非依存 / storage・transport 注入)。一時 id (負数) の実 id 再割当てと連鎖 rollback も実装 (Phase 4)
- `linear/client/src/sync-engine.test.ts` — 楽観反映 / 4xx rollback / offline replay + remap / 依存連鎖破棄 / gap 自己修復 / 永続化復元 の 14 ケース
- `linear/shared/src/reducer.test.ts` — applyOp / applyCommand の純関数性・決定性
- Playwright（Phase 5 予定）— offline 編集 → 再接続 → 他 context に反映、の実機 E2E

## 関連 ADR

- ADR 0002: 真実は server log。client_mutation_id 冪等台帳が再送を吸収
- ADR 0004: reducer / スキーマを shared/ に置き FE/BE で意味を揃える
- ADR 0005: WS は通知経路。連続性が崩れたら delta で自己修復
