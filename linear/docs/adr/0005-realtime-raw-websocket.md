# ADR 0005: realtime 配信は素の WebSocket — COMMIT 後 broadcast + catch-up 自己修復

## ステータス

Accepted（2026-06-10）

## コンテキスト

確定した op を workspace 内の他 client へ届ける経路の選定。本リポは streaming 方式の比較学習を重ねてきた: slack/figma = ActionCable (WS)、discord/uber = Go 素 WS、perplexity = SSE、youtube/github = polling。

本プロジェクトの特性:

- 配信するのは **seq 付き op** で、client は `lastSyncId` の連続性を自分で検証できる (ADR 0002/0003)。つまり**配信経路は at-most-once で良く、信頼性は catch-up が持つ**
- mutation の送信は HTTP POST であり、サーバ→クライアント方向さえあれば成立する
- 切断検知が速いほど「offline 編集モード」への切替が機敏になる (ADR 0003)

## 決定

**素の WebSocket (`@nestjs/websockets` + `@nestjs/platform-ws`) を採用する**。

- 接続: `ws://…/sync?workspace=W` + JWT (接続時に検証)。room 管理は gateway 内の `Map<workspaceId, Set<socket>>` (単一プロセス前提、discord の Hub と同形)
- 配信: mutation の **COMMIT 後**に room へ `{ type: "op", op, seq }` を push。**push はヒントであり真実は log** — 取りこぼしは client が seq 連続性で検出し `delta` で自己修復 (figma ADR 0003 と同じ「commit 後 broadcast + catch-up」構成)
- 死活: server から ping、client は pong。client 側は指数 backoff で再接続し、再接続後は必ず delta catch-up してから受信を再開
- 自分の mutation の confirm も WS 経由の op で受ける (HTTP レスポンスと WS の二重適用は `client_mutation_id` / seq で冪等)

## 検討した選択肢

### 1. 素の WebSocket ← 採用

- 標準プロトコル。再接続・catch-up・heartbeat を**自前で書くこと自体が学習対象** (sync engine の再接続設計は隠したら学べない)
- 双方向なので ping/pong による切断検知と、将来の presence (誰がどの issue を見ているか) に発展できる

### 2. socket.io

- 実務で頻出。room / 自動再接続 / fallback が組み込み済みで実装は最速
- 欠点: 独自プロトコルで wire が標準 WS でなくなる。**自動再接続と受信バッファが「再接続 = delta catch-up が必要」という本プロジェクトの核心をライブラリの影に隠す**。学習目的と正面衝突する

### 3. SSE (Server-Sent Events)

- mutation が HTTP POST なので server→client 片方向で機能的には足りる。perplexity で実装済みの経路
- 欠点: 片方向ゆえ ping/pong の切断検知が弱く offline 切替が鈍る。HTTP/1.1 ではブラウザのホスト毎同時接続数制限に当たりやすい (タブ複数で枯渇)。SSE の学びは perplexity で獲得済みで重複する

### 4. polling (delta を定期取得)

- 最も単純で、delta API だけで完結する
- 欠点: リアルタイム協調の体感 (数百 ms で他者の変更が映る) が出ない。ただし**障害時の最終フォールバックとしての delta polling は本設計に内在**している (WS が死んでも収束は壊れない)

## 採用理由

- **学習価値**: 「unreliable push + reliable log」という実物の sync engine と同じ構成を、再接続・heartbeat・連続性検証まで含めて自前実装する。ActionCable (figma) / Go Hub (discord) と並ぶ **3 つ目の WS 実装形** として比較が成立する
- **アーキテクチャ妥当性**: Linear 本家も WS push + 差分 sync。配信の信頼性を log 側に寄せて push を軽くするのは実務の定石
- **責務分離**: `realtime` module は「room 管理と push」だけを持ち、順序・冪等の正しさは一切持たない (ADR 0002 が持つ)。配信が死んでもデータは壊れない
- **将来の拡張性**: presence / typing indicator は同じ gateway に ephemeral メッセージとして足せる (figma の ephemeral cursor と同判断)

## 却下理由

- socket.io: 学習の核心 (再接続と catch-up の結合) を隠蔽する。独自 wire も不要
- SSE: perplexity との重複学習 + 切断検知・接続数の制約。WS の方が本題材に適合
- polling 単独: リアルタイム体感の放棄。fallback としては設計に内在済み

## 引き受けるトレードオフ

- **自前実装の手間**: 再接続 backoff / ping-pong / room 掃除をすべて書く。これは対価ではなく目的
- **単一プロセス前提**: room が in-memory Map なので backend は 1 プロセス (ローカル完結スコープ)。複数プロセス化には Redis pub/sub 等の中継が必要 — Terraform 設計図で言及するに留める
- **at-most-once push**: COMMIT と push の間にプロセスが落ちると push は消える。client の連続性検証 + delta 修復で吸収する設計なので、push の信頼性向上 (再送 buffer 等) はあえて作らない

## このADRを守るテスト / 実装ポインタ

- `linear/backend/test/realtime.e2e-spec.ts` — 2 接続 fan-out / 冪等 replay は再 broadcast しない / 再接続 hello → delta catch-up / 4400・4401・4403 close (Phase 3 で実装・pass)
- `linear/backend/src/realtime/` — gateway (接続時 JWT + membership 検証 → hello) と RealtimeService (room Map + heartbeat + broadcastOps)。順序・冪等の正しさは持たない
- `linear/frontend/`（予定）— WSClient: 連続性が崩れた時に delta を先に当ててから適用再開すること
- Playwright（Phase 5 予定）— 2 BrowserContext hstack で issue 移動の即時反映 (リポ慣行の実機 E2E)

## 関連 ADR

- ADR 0002: 真実は sync log。push は配達保証を持たない
- ADR 0003: 再接続シーケンス (catch-up → rebase → replay)
- figma ADR 0003 / discord Hub: 本リポ内の WS 実装 3 形の比較対象
