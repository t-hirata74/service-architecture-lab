# Linear 風 issue tracker (TypeScript フルスタック: NestJS + Next.js)

Linear を参考に、**「server 権威 sync log による delta sync + optimistic update / offline 耐性 (sync engine)」** をローカル環境で再現するプロジェクト。本リポ初の **TypeScript backend** (NestJS) であり、frontend / backend / 共有スキーマを 1 つの npm workspaces monorepo として構成する。

外部 SaaS / LLM は使用せず、ai-worker 側で deterministic な mock を実装することでローカル完結を保つ（リポ全体方針: [`../CLAUDE.md`](../CLAUDE.md)）。

---

## 見どころハイライト

> 🔴 **設計フェーズ**: ADR 0001-0005 起こし済み。実装は Phase 2 から。

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

## ADR

| # | 決定 |
| --- | --- |
| [0001](docs/adr/0001-typescript-backend-nestjs-prisma.md) | TS backend に NestJS (Express platform) + Prisma を採用し module を責務分割 |
| [0002](docs/adr/0002-sync-log-per-workspace-seq.md) | per-workspace `seq` の sync log — counter 行 `FOR UPDATE` 採番で gapless 全順序 |
| [0003](docs/adr/0003-client-sync-optimistic-offline.md) | client 同期 — optimistic queue + rebase + offline replay (`clientMutationId` 冪等) |
| [0004](docs/adr/0004-monorepo-shared-zod-types.md) | npm workspaces monorepo + `shared/` zod スキーマで FE/BE 型共有 |
| [0005](docs/adr/0005-realtime-raw-websocket.md) | realtime 配信は素の WebSocket — COMMIT 後 broadcast + 取りこぼしは catch-up で吸収 |

---

## ローカル起動

```sh
# TODO: Phase 2 以降で更新する。現時点では MySQL のみ起動できる:
docker compose up -d        # mysql :3330
```

---

## 初期化コマンド（プロジェクト初期化時に実行）

<!-- このセクションは初期化が終わったら削除する -->

```sh
# monorepo root (linear/) — npm workspaces
npm init -y                       # 後で "workspaces": ["shared", "backend", "frontend"] を追記
# backend (NestJS)
npx @nestjs/cli new backend --package-manager npm
# frontend (Next.js)
npx create-next-app@latest frontend --ts --app --tailwind
# shared (型共有 package)
cd shared && npm init -y          # zod を依存に追加
# backend ORM
cd backend && npx prisma init --datasource-provider mysql
# ai-worker (Python)
cd ai-worker && python3 -m venv .venv && .venv/bin/pip install fastapi uvicorn pytest
```

---

## ポート割当

| コンポーネント | ポート |
| --- | --- |
| MySQL 8 | 3330 |
| backend (NestJS) | 3140 |
| frontend (Next.js) | 3145 |
| ai-worker (FastAPI) | 8130 |
