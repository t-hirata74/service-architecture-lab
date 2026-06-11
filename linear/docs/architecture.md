# linear アーキテクチャ

> 🟢 MVP 完成 (Phase 1-5)。設計どおり実装され、各 ADR の「このADRを守るテスト」が実体を指す。

Linear 風 issue tracker。技術課題の中核は **sync engine** — server 権威の全順序 op log を真実とし、client は materialized snapshot + 差分 catch-up + optimistic update で「即時に反応し、最終的に必ず一致する」UI を作る。

## ドメイン境界

NestJS module 単位で境界を切る (ADR 0001)。

| module | 責務 | 依存先 |
| --- | --- | --- |
| `auth` | signup / login / JWT 発行・検証 (認証 1 経路) | `prisma` |
| `workspaces` | workspace / membership の読み取り・認可 guard | `prisma` |
| `teams` | team / workflow_states / labels の管理 | `prisma`, `sync` |
| `issues` | issue / comment のドメインロジック (番号採番・fractional order) | `prisma`, `sync` |
| `mutations` | **書き込みの唯一の入口** `POST /mutations`。コマンドを dispatch し sync log へ | `issues`, `teams`, `sync` |
| `sync` | sync_ops append (採番) / bootstrap / delta の提供 | `prisma` |
| `realtime` | WS gateway。workspace room 管理と COMMIT 後 op broadcast | `sync` |
| `ai` | ai-worker への triage / duplicate 問い合わせ (graceful degradation) | — |
| `prisma` | PrismaService (global) | — |

**依存方向の規律**: ドメイン module (`issues` / `teams`) は `realtime` を知らない。broadcast は `mutations` が COMMIT 後に `realtime` へ通知する一方向 (shopify の `ActiveSupport::Notifications` による依存逆転と同じ意図を、Nest の event なしで単純な呼び出し順で実現する)。

書き込みがすべて `POST /mutations` を通るのが本プロジェクトの特徴で、REST の資源別 endpoint は読み取り専用 (bootstrap / delta / 個別 GET) に限る。理由は ADR 0002 (全 mutation を漏れなく log に乗せるため、入口を 1 つにする)。

## データモデル

```text
users               id / email / password_hash / name
workspaces          id / name / url_key / sync_seq (BIGINT, 採番カウンタ)
workspace_members   workspace_id / user_id / role (admin|member)
teams               id / workspace_id / key ("ENG") / name / issue_counter (BIGINT)
workflow_states     id / team_id / name / category (backlog|unstarted|started|completed|canceled) / position
issues              id / team_id / number / title / description / state_id / priority (0-4)
                    / assignee_id? / sort_order (fractional index 文字列) / created_by
labels              id / team_id / name / color
issue_labels        issue_id / label_id
comments            id / issue_id / author_id / body
sync_ops            id / workspace_id / seq / entity_type / entity_id
                    / action (insert|update|delete) / payload JSON / actor_id
                    / client_mutation_id? / created_at   ← append-only
                    UNIQUE(workspace_id, seq)
mutations           id / client_mutation_id UNIQUE / workspace_id / actor_id
                    / first_seq / last_seq / created_at  ← 冪等台帳
```

- **二層構造** (figma ADR 0002 と同思想): `issues` 等の materialized 現在状態 + `sync_ops` の append-only 履歴。bootstrap は materialized から、catch-up は log から返す。
- **`workspaces.sync_seq`** が lastSyncId の採番元。トランザクション内で行ロック (`FOR UPDATE`) → seq 確定 → ops INSERT → COMMIT。ロックを commit まで保持することで **commit 順 = seq 順** になり、delta 読者が gap を踏まない (ADR 0002)。
- **`teams.issue_counter`** で `ENG-42` 形式の番号を原子採番 (shopify `Order#number` の counter カラム方式の TS 版)。
- **1 mutation → N ops**: 例えば「ラベル付きで issue 作成」は issue insert + issue_labels insert の連続 seq になる。`mutations` 台帳が `client_mutation_id` UNIQUE で重複実行を弾き、replay には記録済み結果を返す。
- **activity feed は projection**: issue 詳細の変更履歴は `sync_ops` を `entity_id` で引いて表示する。専用テーブルを持たない。

## 主要フロー

### 1. mutation (オンライン時)

```text
client: 楽観適用 (shared/ の reducer) → pending queue へ → POST /mutations
server: 1 txn [ workspace 行 FOR UPDATE → seq 採番 → ドメイン更新 + sync_ops INSERT
                + mutations 台帳 INSERT ] → COMMIT → workspace room へ WS broadcast
client: WS で自分の op を受信 → client_mutation_id が pending と一致 → confirm して pending を除去
他 client: op を受信 → lastSyncId 連続性を確認して適用
```

### 2. bootstrap / delta catch-up

```text
初回:        GET /sync/bootstrap?workspace=W → 全 entity snapshot + lastSyncId
再接続/復帰: GET /sync/delta?workspace=W&since=N → ops[N+1..] + lastSyncId
WS 受信中:   op.seq が lastSyncId+1 でなければ取りこぼし → delta で埋めてから適用
```

### 3. オフライン編集 → 復帰

```text
オフライン: 楽観適用 + pending queue (IndexedDB 永続) に蓄積
復帰:       (1) delta catch-up で server 状態に追従
            (2) pending を base に再適用 (rebase) して UI を再構成
            (3) pending を順に POST (at-least-once。重複は mutations 台帳が吸収)
```

### 4. ai-worker triage (非同期・任意機能)

issue 作成後に backend → ai-worker `/triage` へ title/description を渡し、優先度・ラベル提案と duplicate 候補を受け取って suggestion として表示する。ai-worker 停止時は提案なしで継続 (graceful degradation、内部 ingress + 共有トークンは他プロジェクトと同形)。

## 失敗時の挙動

| 失敗 | 挙動 |
| --- | --- |
| mutation が server で拒否 (validation / 権限) | 4xx を受けた client は該当 pending を破棄し、base + 残 pending で再構成 (rollback)。toast 表示 |
| WS 切断 | 指数 backoff で再接続 → `since=lastSyncId` の delta catch-up → 通常受信へ復帰 |
| mutation POST のタイムアウト後の再送 | `client_mutation_id` UNIQUE に当たり、台帳の記録済み結果を返す (no-op) |
| broadcast の取りこぼし (COMMIT 後 push の隙間) | client が seq 連続性で検出し delta で自己修復。push は「ヒント」、真実は log |
| ai-worker 停止 | triage 提案なしで本流継続 |

## ローカル運用

| コンポーネント | ポート | 起動 |
| --- | --- | --- |
| MySQL 8 | 3330 | `docker compose up -d` |
| backend (NestJS) | 3140 | `npm run start:dev -w backend` |
| frontend (Next.js) | 3145 | `npm run dev -w frontend` |
| ai-worker (FastAPI) | 8130 | compose に同梱 |

## 学びログ

- **AUTO_INCREMENT は commit 順を保証しない、を対策込みで手で書けた** — counter 行 `FOR UPDATE` 採番 (ADR 0002) は、並行 30 mutation 下で delta 読者が gap を観測しない不変条件テストで固定した。outbox / CDC 設計に通じる、このプロジェクト最大の学び。
- **「confirmed + pending 分離」が optimistic UI の正攻法だと体感した** — rollback を「逆操作の生成」でなく「pending から外して再導出」にしたことで、4xx 拒否・連鎖破棄・rebase が全部同じ仕組みに畳まれた (ADR 0003)。一時 id の位置対応 remap (createTeam → その temp team への createIssue) が一番設計を要した。
- **reducer parity テストは FE/BE 型共有の「本当の価値」を示す** — スキーマ共有 (型が合う) だけでなく「bootstrap(0) + 全 ops 畳み込み ≡ 最終 bootstrap」で意味の一致まで実 DB で固定できた (ADR 0004)。
- **push を諦める設計は強い** — WS push を at-most-once のヒントに格下げし真実を log に置いた (ADR 0005) ことで、再接続・取りこぼし・複数デバイスが全部「delta で埋める」の 1 パターンに集約。Playwright の offline replay が素直に通ったのはこの単純さのおかげ。
- **TS フルスタックの罠は toolchain に集中する** — `import type` (TS1272) / supertest の default import / Prisma shadow DB / jest `--runInBand` / WsAdapter の test 側適用 / `unref()` / react-hooks v6 の set-state-in-effect。ドメインロジックより環境構築で詰まる、という実務感覚を得た。
- **宿題**: WS 配信の水平化 (Redis pub/sub 中継)、snapshot checkpoint + 古い op の truncate、undo/redo (pending queue の上に載る)、複数 tab の BroadcastChannel 同期。
