# Linear 風 issue tracker (TypeScript フルスタック: NestJS + Next.js)

Linear を参考に、**「server 権威 sync log による delta sync + optimistic update / offline 耐性 (sync engine)」** をローカル環境で再現するプロジェクト。本リポ初の **TypeScript backend** (NestJS) であり、frontend / backend / 共有スキーマを 1 つの npm workspaces monorepo として構成する。

外部 SaaS / LLM は使用せず、ai-worker 側で deterministic な mock を実装することでローカル完結を保つ（リポ全体方針: [`../CLAUDE.md`](../CLAUDE.md)）。

---

## 見どころハイライト

> 🟢 **MVP 完成** (Phase 1-5) **+ E1 メンバー招待/権限** (ADR 0006): server 権威 sync log (gapless 採番 + 冪等台帳) ⇄ client SyncEngine (optimistic / offline replay / temp id remap) を、Next.js UI (kanban + command palette + AI triage + メンバー管理/workspace 切替) と **実機フルスタック Playwright 3 件** (realtime fan-out / offline replay / 招待コラボ) で動作確認済み。jest e2e 35 + vitest 41 + pytest 9 + Terraform validate + CI 5 ジョブ。

- **server 権威 sync log** — 全 mutation を per-workspace `seq`(= `lastSyncId`) で全順序化した append-only log に記録。採番は workspace 行の `FOR UPDATE` ロックで commit 順 = seq 順を保証し、delta 読み飛ばし (gap) を構造的に排除する（[ADR 0002](docs/adr/0002-sync-log-per-workspace-seq.md)）
- **bootstrap + delta sync** — 初回は materialized snapshot を全量、以降は `?since=seq` の差分 catch-up。WS 切断からの再接続も同じ経路で吸収（[ADR 0002](docs/adr/0002-sync-log-per-workspace-seq.md) / [ADR 0005](docs/adr/0005-realtime-raw-websocket.md)）
- **optimistic update + rollback + offline queue** — client は mutation を即ローカル適用し、server 確定 op で confirm、拒否なら巻き戻す。オフライン編集は IndexedDB の pending queue に永続化して再接続時に replay、`clientMutationId` UNIQUE で at-least-once を冪等に吸収（[ADR 0003](docs/adr/0003-client-sync-optimistic-offline.md)）
- **zod スキーマの FE/BE 共有** — mutation 引数 / op payload / WS メッセージを `shared/` workspace で単一定義し、backend の validation pipe と frontend のフォーム検証が同じスキーマを使う（[ADR 0004](docs/adr/0004-monorepo-shared-zod-types.md)）
- **figma (LWW-CRDT) との対比** — 「リアルタイム協調 3 流派 (CRDT / OT / sync log)」のうち sync log 担当。収束を client 側 merge ではなく **server の全順序**で取る設計差を学ぶ
- **local-first の体感** — 検索・フィルタは IndexedDB キャッシュ上で完結し、サーバ往復なしで即応答する

### ボリューム方針 (初 TS フルスタックのため学習面積を広く取る)

最小 MVP に絞らず、各機能が sync engine を通る形で実装範囲を広げる:

| 機能 | 学習ポイント |
| --- | --- |
| per-team issue number (`ENG-42`) | team 行カウンタの原子採番 (shopify `Order#number` の TS 版) |
| kanban 並び順 (fractional indexing) | `sort_order` 文字列キーの中間挿入 — 本リポ初 |
| activity feed | `sync_ops` log の projection として issue 履歴を表示 (追加テーブルなし) |
| command palette (Cmd+K) + キーボード操作 | Linear らしさ / frontend 設計の練習 |
| ai-worker triage | 優先度・ラベル提案 + duplicate 検出 (deterministic mock) |

---

## アーキテクチャ概要

```mermaid
flowchart LR
  user([Browser])
  subgraph frontend [frontend : Next.js 16 :3145]
    store[SyncStore<br/>IndexedDB + optimistic queue]
  end
  subgraph backend [backend : NestJS :3140]
    mut[Mutations API<br/>POST /mutations]
    sync[Sync API<br/>bootstrap / delta]
    ws[WS Gateway<br/>per-workspace room]
    log[(sync_ops<br/>append-only)]
  end
  shared[[shared/ : zod スキーマ<br/>FE/BE 共有]]
  ai[ai-worker : FastAPI :8130<br/>triage / duplicate mock]
  db[(MySQL 8 :3330)]

  user --> store
  store -- "mutation (clientMutationId)" --> mut
  store -- "初回 / 再接続 catch-up" --> sync
  ws -- "op push (seq 順)" --> store
  mut --> log
  log --> db
  sync --> db
  mut -- "COMMIT 後 broadcast" --> ws
  mut -. "triage 提案" .-> ai
  frontend -.型.- shared
  backend -.型.- shared
```

設計の詳細は [`docs/architecture.md`](docs/architecture.md)、判断の経緯は [`docs/adr/`](docs/adr/)。

---

## E2E デモ (Playwright で録画)

2 BrowserContext (Device A | Device B、同一ユーザの 2 デバイス) を ffmpeg hstack で並べた実機フルスタック録画。

### 1. realtime fan-out — 作成・移動が他デバイスへ即時反映

左 (A) で issue 作成 → 楽観反映の直後に server 確定で `GEN-1` が付き、右 (B) には WS push (op) で届く。→ ボタンで Todo へ移動すると B のカードも列を移る。

![realtime fan-out](playwright/captures/01-realtime-fanout.gif)

### 2. offline replay — オフライン編集が復帰後に同期

A をオフライン化して issue を作成 — 「保存中…」バッジ付きで楽観表示され、B には届かない。復帰すると pending queue が replay され (`clientMutationId` 冪等)、A に番号が付き B にも現れる。

![offline replay](playwright/captures/02-offline-replay.gif)

### 3. 招待コラボ (E1) — 別ユーザを招待して同じ board を共同編集

左 (Alice) が members パネルから Bob を email 招待 → 右 (Bob) は workspace switcher で Alice Workspace へ切替 → Alice の issue 作成が Bob へ realtime 反映。招待は **server-resolved コマンド (楽観適用しない)** の例 (ADR 0006)。

![collaboration](playwright/captures/03-collaboration.gif)

---

## ADR

| # | 決定 |
| --- | --- |
| [0001](docs/adr/0001-typescript-backend-nestjs-prisma.md) | TS backend に NestJS (Express platform) + Prisma を採用し module を責務分割 |
| [0002](docs/adr/0002-sync-log-per-workspace-seq.md) | per-workspace `seq` の sync log — counter 行 `FOR UPDATE` 採番で gapless 全順序 |
| [0003](docs/adr/0003-client-sync-optimistic-offline.md) | client 同期 — optimistic queue + rebase + offline replay (`clientMutationId` 冪等) |
| [0004](docs/adr/0004-monorepo-shared-zod-types.md) | npm workspaces monorepo + `shared/` zod スキーマで FE/BE 型共有 |
| [0005](docs/adr/0005-realtime-raw-websocket.md) | realtime 配信は素の WebSocket — COMMIT 後 broadcast + 取りこぼしは catch-up で吸収 |
| [0006](docs/adr/0006-membership-and-protocol-evolution.md) | メンバーシップ (E1) — protocol の lockstep 進化 / server-resolved コマンドは楽観しない / users は membership 従属 / 除外は WS kick |

---

## ローカル起動

```sh
# 1. MySQL :3330 (初回は linear_test / linear_shadow も自動作成)
docker compose up -d

# 2. 依存インストール (monorepo root で。shared/backend に一括で入る)
npm install

# 3. backend 環境変数と migration
cp backend/.env.example backend/.env
cd backend && npx prisma migrate dev && cd ..

# 4. packages を build して backend (NestJS :3140) と frontend (Next.js :3145) を起動
npm run build:packages
npm run start:dev -w backend
npm run dev -w frontend          # 別タブ → http://localhost:3145

# 動作確認
curl http://localhost:3140/health
# WS は ws://localhost:3140/sync/ws?workspaceId=<id>&token=<JWT> (hello → op push)
```

```sh
# E2E (実機フルスタック / webServer が backend・frontend を production build で起動)
cd playwright && npm install && npm test
npm run capture                  # gif 録画 (ffmpeg 必須)
```

```sh
# テスト / lint (root の Makefile からは make linear-test / make linear-lint)
npm run test -w @linear/shared      # vitest (fractional fuzz + schema + reducer)
npm run test -w @linear/client-sync # vitest (SyncEngine: optimistic/offline/remap)
npm run test -w backend             # jest unit
npm run test:e2e -w backend         # jest e2e (linear_test DB / --runInBand)
npm run lint                        # eslint + tsc --noEmit
cd ai-worker && .venv/bin/python -m pytest   # ai-worker (要 venv セットアップ)
```

---

## ポート割当

| コンポーネント | ポート |
| --- | --- |
| MySQL 8 | 3330 |
| backend (NestJS) | 3140 |
| frontend (Next.js) | 3145 |
| ai-worker (FastAPI) | 8130 |
