# ADR 0003: ActionCable + Solid Cable で op fan-out / cursor は ephemeral

## ステータス

Accepted（2026-06-03）

## コンテキスト

ADR 0001 / 0002 で「op を server で適用 → 全 collaborator に配る」構図が決まった。**どの配信基盤で fan-out するか**、**cursor（他者ポインタ）をどう扱うか**が本 ADR の論点。

制約・前提:

- バックエンドは Rails 8。リアルタイム配信は **ActionCable** が第一候補。
- `slack`（本リポ既存）は ActionCable を **Redis adapter** で動かし、append-only メッセージを fan-out している。figma は同じ ActionCable でも「収束する op」を運ぶので、**実装比較が学習素材**。
- 本番は Puma 複数プロセス / 複数ノード。fan-out は単一プロセス memory を跨ぐ必要がある。
- ローカル完結 + Redis 非依存を保ちたい（本リポは youtube / shopify / zoom で Solid Queue を採用し「Rails 8 / DB-driven / Redis なし」の系譜がある）。
- cursor は秒間多数飛ぶ高頻度・低価値（消えても良い）データ。op log とは性質が真逆。

## 決定

**ActionCable + Solid Cable（Rails 8 標準の MySQL backed adapter）** で op を fan-out し、**cursor は永続化しない別メッセージ型** にする。

- `DocumentChannel`: `subscribed` で `stream_for document`（document 単位の購読）。
- client → server action:
  - `apply_operation(data)` — OperationApplier（ADR 0002）を 1 txn で実行 → COMMIT 後に `operation`（seq 付き）を broadcast。
  - `cursor(data)` — **DB に触れず**、actor 情報を付けてそのまま rebroadcast。
- server → client broadcast:
  - `operation` — `{object_id, op_type, payload, lamport, seq, actor_id}`。
  - `cursor` — `{actor_id, name, x, y}`（ephemeral、op log にも `canvas_objects` にも載らない）。
- **catch-up は REST**（`GET /documents/:id/operations?since=N`、ADR 0002）。WS の取りこぼしは client が seq gap で検出して補完。
- adapter は `config/cable.yml` で `solid_cable`。Solid Cable / Queue / Cache は同一 MySQL に同居（single-DB）。

## 検討した選択肢

### 1. ActionCable + Solid Cable / cursor ephemeral ← 採用

- Redis なしで複数プロセスを跨ぐ fan-out（Rails 8 標準）。本リポの「Rails 8 / DB-driven」系譜に整合。
- `slack`（Redis adapter）との **adapter 対比**がそのまま学習素材。
- cursor を非永続にすることで op log を「意味のある編集」だけに保てる。

### 2. ActionCable + Redis adapter（slack と同じ）

- 低レイテンシ pub/sub（poll なし）。大規模 fan-out の実績。
- 欠点: Redis という追加インフラ。slack で既に扱った adapter なので学習の新規性が薄い。figma では **Solid Cable を試す**方が対比価値が高い。

### 3. cursor を op log に載せる（一元化）

- 配信経路が 1 本になる。
- 欠点: 高頻度・揮発データで `operations` が汚染され肥大。LWW 適用や seq 採番のコストも無駄。却下。

### 4. SSE / 生 WebSocket 自前実装

- ActionCable の抽象を外して低レベル制御。
- 欠点: Rails の標準から外れ、認証（ADR 0004）や stream 管理を再発明する。Rails 学習主旨に反する。

## 採用理由

- **学習価値**: Rails 8 の **Solid Cable** を実地検証し、`slack` の Redis adapter と「同じ ActionCable API / 違う adapter」を対比できる。op（収束・永続）と cursor（揮発）で**配信経路を性質ごとに分ける**設計判断が手で書ける。
- **アーキテクチャ妥当性**: 「永続 op は durable に、presence/cursor は ephemeral に」は協調編集の定石（Figma も cursor は揮発）。
- **責務分離**: op の durability（DB + seq）と cursor の即時性（fan-out only）を混ぜない。
- **将来の拡張性**: レイテンシが問題化すれば adapter を Redis に差し替え可能（`cable.yml` の 1 行）。比較データが ADR に残る。

## 却下理由

- 案 2（Redis adapter）: slack で扱い済み。Solid Cable の方が新規学習 + Redis 非依存。
- 案 3（cursor を log に）: 揮発高頻度データで op log を汚染。
- 案 4（自前 WS）: Rails 標準を捨てる学習コストが見合わない。

## 引き受けるトレードオフ

- **Solid Cable の poll latency**: DB ポーリング由来で Redis pub/sub よりレイテンシが大きい（既定 ~0.1s オーダー）。リアルタイム編集には体感上ギリギリ許容だが、シビアなら Redis へ。**この trade-off の計測自体が学習対象**。
- **DB 負荷**: cursor の高頻度 broadcast は Solid Cable の polling 負荷を上げ得る。cursor は client 側 throttle（~30–50ms）+ broadcast-only（DB 書き込みなし）で緩和。
- **at-least-once / 取りこぼし**: WS は再接続前提。client が seq gap を検出して REST catch-up で吸収（exactly-once は保証しない、LWW で再適用は冪等）。
- **メッセージ順序**: Solid Cable は厳密な全順序を保証しないが、**収束は lamport に依存し配信順に依存しない**（ADR 0001）ので問題にならない。`seq` で client 側整列も可能。

## このADRを守るテスト / 実装ポインタ

- `figma/backend/spec/channels/document_channel_spec.rb`（予定）— `apply_operation` で broadcast が飛ぶ / viewer の op は拒否 / `cursor` は DB に書かない。
- `figma/backend/config/cable.yml`（予定）— `adapter: solid_cable`。
- `figma/playwright/tests/converge.spec.ts`（予定）— 2 BrowserContext で同一オブジェクトを同時編集 → 両画面が同一状態に収束（hstack で gif）。

## 関連 ADR

- ADR 0001: 整合性（収束は lamport 依存なので配信順に頑健）
- ADR 0002: op 適用（COMMIT 後に broadcast、catch-up は `?since=seq`）
- ADR 0004: 認証（ActionCable connection の identification）
