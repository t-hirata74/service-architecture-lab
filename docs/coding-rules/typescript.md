# TypeScript フルスタック コーディング規約 / 選定判断

`linear/`（npm workspaces monorepo: `shared` / `client` / `backend`=NestJS / `frontend`=Next.js）で実際に採用した規約と、**「いつ TypeScript フルスタックを選ぶか」「TS で何を学ぶか」** の判断軸をまとめる。Rails / Python / Go を含めた選定の中で **TS フルスタックの役回りを明確にする** のが目的。

---

## 1. いつ TypeScript フルスタックを選ぶか (技術判断)

TS フルスタックの固有価値は **「FE と BE が同じ型・同じロジックを共有できる」** ことに尽きる。それが学習・設計の主題でないなら、backend は Rails / Go / Python のほうが適することが多い。

### 選ぶ基準

以下のうち **1 つ目を含む 2 つ以上**が当てはまるなら TS フルスタックの出番。

| 基準 | 例 | 他言語 backend との比較 |
| --- | --- | --- |
| **FE/BE の契約そのものが設計の主役** (protocol / コマンド / スキーマ) | linear の sync protocol (mutation / op / bootstrap / WS message) | OpenAPI codegen でも型は渡せるが、**zod なら 1 定義 = 型 + 両側のランタイム検証**になり、生成ステップも消える |
| **同じロジックをブラウザとサーバの両方で動かす** | 楽観適用 reducer (`applyOp` / `applyCommand`)、fractional indexing | 他言語だと二重実装 + ドリフト。TS は共有して **parity テスト**で意味の一致まで固定できる (§7) |
| **リアルタイム / streaming の BFF 層** (WS / SSE relay) | op push、LLM token relay | Node のイベントループは I/O 多重に強い。CPU 並行が要るなら Go (go.md §1) |
| **「Node 版実務標準」の体得が目的** | NestJS (DI / module / guard / pipe) | Rails の Convention に相当する構造を TS でどう作るかの教材として NestJS が最適 |

### 選ばない基準

- **CRUD + 管理画面 + フォーム中心** — Rails (generator / AR / strong params) が圧倒的に速い
- **CPU 並行・メモリ常駐の状態機械** — GIL ならぬ単一イベントループで詰まる。Go へ (go.md)
- **ML / データ処理 / 数値計算** — Python へ
- **FE が薄い (ダッシュボード 1 枚など)** — 型共有の利得が出ず、monorepo の手間だけ残る

### 本リポでの採用例

- **linear (MVP 完成)** — server 権威 sync log ⇄ optimistic/offline client。「FE/BE が同じ契約・同じ reducer を共有しないと成立しない」題材で、TS 固有価値が最大化される。Rails (8 本) との対比で「Node 版 Rails としての NestJS」も検証した (§9)

---

## 2. monorepo 構成 (npm workspaces)

```text
linear/
  package.json        # "workspaces": ["shared", "client", "backend", "frontend"]
  shared/             # zod スキーマ + 共有純ロジック (reducer / fractional)。両側から import
  client/             # framework 非依存の sync engine (React を import しない)
  backend/            # NestJS
  frontend/           # Next.js (React バインドはここ)
```

- **workspace ツールは npm 標準** — pnpm / turborepo は導入しない。3〜4 workspace 規模では npm で困らず、リポ全体の `npm ci` 慣行 (CI 含む) と割れない。スケールしたら移行は機械的にできる
- **shared / client は dist 配布** (`main`/`types` → `dist/`)。Nest (tsc) は node_modules 下の TS をコンパイルしないため、ソース直参照は tsconfig paths 地獄になる。**consumer の起動・テスト前に `npm run build:packages` が必須** — Makefile / CI / Playwright webServer のコマンドに焼き込んで吸収する
- **依存方向は一方向**: `shared` ← `client` / `backend` / `frontend`。`client` が React を import したら設計違反 (React バインドは frontend の `useSyncExternalStore` だけ)
- **契約は zod 単一定義** — スキーマが「TS 型 (`z.infer`) + backend 入力検証 + frontend フォーム/受信検証」の 3 役を兼ねる。tRPC は HTTP の形がランタイムに隠れ WS と二重化する、OpenAPI codegen は WS をカバーできず生成物管理が増える、という判断 (linear ADR 0004)

---

## 3. NestJS 規約 (backend)

- **module = 責務境界**。依存方向を module の import 関係で表現する。linear では「書き込みの唯一の入口」を mutations module に置き、ドメイン module (issues / teams) は realtime を import しない (broadcast は mutations が COMMIT 後に呼ぶ一方向)
- **認証はデフォルト必須**: `APP_GUARD` に JwtAuthGuard、公開 endpoint は `@Public()` で opt-out を明示。「付け忘れて漏れる」を構造で防ぐ
- **validation は class-validator でなく zod pipe**: `@Body(new ZodValidationPipe(SchemaFromShared))`。Nest 公式の慣習から外れる代わりに、契約の単一定義 (§2) を取る
- **デコレータ署名で参照する型は `import type` 必須** — `isolatedModules` + `emitDecoratorMetadata` の組合せで TS1272 になる。値 import と型 import を行で分ける
- **素の WebSocket は `@nestjs/platform-ws`** (socket.io を使わない判断は linear ADR 0005)。注意点:
  - `app.useWebSocketAdapter(new WsAdapter(app))` を **main.ts とテスト helpers の両方**に書く (テストだけ素通りして謎の 404 になる)
  - 接続時認証は `handleConnection` 内で行う。**`APP_GUARD` は lifecycle hook には効かない** (message handler のみ)
  - ブラウザ WebSocket はヘッダを付けられないので token は query param (本番なら一時 ticket 化)
  - heartbeat の `setInterval` は **`unref()`** しないと jest がハングする
- **HTTP 例外の使い分け**: 対象が無い=404 / メンバーでない=403 / 重複=409 / 形は正しいが意味が通らない=422 / スキーマ違反=400 (zod pipe)

---

## 4. Prisma 規約

- `schema.prisma` が DB の単一源泉。カラム/テーブルは `@map`/`@@map` で snake_case に寄せる (Rails 慣行と揃う)
- **行ロック API が無い** — `SELECT ... FOR UPDATE` は `$queryRaw` で書く。生 SQL は採番カウンタ等の 1 箇所に隔離し、コメントで ADR を指す
- **ロックを保持する interactive transaction は `{ maxWait, timeout }` を明示** — 意図的に直列化している書き込み (counter 行ロック) は、並行時にロック待ち + pool 待ちで既定値 (2s/5s) を超え得る
- **BigInt は API 境界で `Number()` に変換** — `JSON.stringify(bigint)` は throw する。DB は BIGINT が正、JS 側は 2^53 まで安全 (ローカル規模では問題なし) という割り切りをコメントに残す
- **MySQL の `prisma migrate dev` は shadow DB が必要** — アプリ用 DB ユーザに CREATE DATABASE 権限が無いと落ちる。`docker-entrypoint-initdb.d` の init SQL で `*_test` / `*_shadow` を作成 + GRANT し、`shadowDatabaseUrl` で指す。**`migrate deploy` は shadow 不要** (CI はこちら)
- **P2002 (UNIQUE 違反) の判定**: `e.meta?.target` は string | string[] | undefined。`String()` で雑に潰すと typed eslint の `no-base-to-string` に当たる — `typeof` 分岐 + `JSON.stringify` で書く

---

## 5. client パッケージ規約 (framework 非依存 engine)

UI から独立した「エンジン」(state machine / sync / cache) は **framework 非依存の workspace に切り出し、副作用を全部注入する**:

- **transport (HTTP) / storage (IndexedDB) / clock / id 採番を constructor 注入** — テストは in-memory 実装 + 固定 clock/uuid で完全に決定的になる (`Date.now` / `crypto.randomUUID` を直接呼ばない)
- **エラーの意味をエラー型で区別**: 4xx = `TransportHttpError` (拒否 → rollback)、それ以外 = リトライ対象。engine がハンドリングを分岐できる
- **React への接続は `useSyncExternalStore` 互換の口** (`subscribe` / `getSnapshot`) を engine 側に持たせる。snapshot は**変化した時だけ参照を更新** (キャッシュ) — 毎回新オブジェクトを返すと無限再レンダリングになる

---

## 6. frontend (Next.js) — frontend.md への追加分

[coding-rules/frontend.md](frontend.md) (urql singleton / 401 redirect / localStorage + synthetic storage event) に加えて:

- **高コストな client singleton (engine / WS client) は `useState(() => new ...)` で 1 度だけ生成** — urql Provider と同じ規律。`useEffect` 内 new は strict mode の二重実行で事故る
- **react-hooks v6 (eslint-config-next) は「effect 内の同期 setState」を error にする**。回避は 3 パターン:
  1. 外部状態 (localStorage / engine) → `useSyncExternalStore` に置き換える
  2. 開閉・対象切替のリセット → `key={...}` で **remount して useState 初期値に任せる**
  3. 非同期結果の反映 → callback 内 setState + `cancelled` フラグ (これは合法)
- **`next/font/google` は使わない** — ビルド時に外部 fetch するためローカル完結方針に反する。design-tokens.md どおり system font stack を CSS で書く
- **WS URL は API URL から導出する** (`http→ws` 置換)。`NEXT_PUBLIC_*` を二重に持たない

---

## 7. テスト (要点)

詳細は [testing-strategy.md の TypeScript フルスタック節](../testing-strategy.md#typescript-フルスタック-linear)。規約として太字の 3 点だけここに置く:

- **jest (Nest 標準) と vitest (packages) の併用は割り切る** — ランナー統一より各エコシステムの標準に乗る
- **DB を共有する e2e は `--runInBand`** (datadog の `go test -p 1` と同じ理由)。supertest は **default import**
- **共有ロジックは parity テストで「意味の一致」まで固定する** — 型が合うだけでは FE/BE のドリフトは防げない。「bootstrap(0) + 全 ops の reducer 畳み込み ≡ 最終 bootstrap」を実 DB で検証する形が linear の核

---

## 8. toolchain の罠 早見表 (linear で実際に踏んだ)

| 症状 | 原因 | 対処 |
| --- | --- | --- |
| `nest build` で TS1272 | デコレータ署名の型を値 import | `import type` に分離 (§3) |
| e2e で `request is not a function` | supertest を `import * as` | default import に |
| `prisma migrate dev` が権限エラー | MySQL で shadow DB を作れない | init SQL で shadow DB 作成 + `shadowDatabaseUrl` (§4) |
| e2e が並走して flake | jest はファイル並列がデフォルト | `--runInBand` (§7) |
| WS が test だけ 404 | WsAdapter 未適用 | test helpers にも `useWebSocketAdapter` (§3) |
| jest が終了しない | `setInterval` が handle を掴む | `unref()` (§3) |
| eslint `set-state-in-effect` | react-hooks v6 | useSyncExternalStore / key-remount / cancelled フラグ (§6) |
| Playwright で video が録れない | 手動 `browser.newContext()` は config の `use.video` を**継承しない** | helpers で `recordVideo` を明示付与 |
| `JSON.stringify` が throw | BigInt 混入 | 境界で `Number()` (§4) |

---

## 9. Rails との対比 (学習用早見表)

| Rails | NestJS (linear) | メモ |
| --- | --- | --- |
| Engine / app ディレクトリ | module | 依存方向を import で明示できるのは Nest が上 |
| autoload + 規約 | DI (provider / constructor injection) | 明示的なぶんボイラープレートは増える |
| `before_action` + Pundit | Guard (`APP_GUARD` + `@Public()`) | 「デフォルト適用 + opt-out」にできるのが利点 |
| strong params / dry-validation | Pipe (ZodValidationPipe) | zod なら FE と定義共有まで行ける |
| `around_action` / Middleware | Interceptor / Middleware | ほぼ 1:1 |
| schema.rb + model | schema.prisma (単一源泉) | 関連の表現力は AR、型生成は Prisma |
| AR migration | `prisma migrate dev` (+ shadow DB) | 自動生成 SQL を必ず目視する点は同じ |
| `with_lock` | `$queryRaw` FOR UPDATE | Prisma に高レベル API が無い (§4) |
| request spec | jest e2e + supertest | `Test.createTestingModule` で DI 差し替え可 |
| credentials / ENV | `@nestjs/config` | テスト都合で `process.env` 直読みする箇所は理由をコメント |

---

## 関連ドキュメント

- [linear ADR 0001-0005](../../linear/docs/adr/) — NestJS/Prisma 採用・sync log・client 同期・型共有・素 WS の判断記録
- [coding-rules/frontend.md](frontend.md) — React / Next.js 共通規約 (本書 §6 はその差分)
- [coding-rules/go.md](go.md) — 「いつ Go か」(§1 の対になる判断軸)
- [operating-patterns.md](../operating-patterns.md) — §26 sync log gapless 採番 / §27 optimistic + offline client
- [testing-strategy.md](../testing-strategy.md) — TypeScript フルスタック節
