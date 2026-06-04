# ADR 0001: Server 権威 + LWW-CRDT による同時編集の収束

## ステータス

Accepted（2026-06-03）

## コンテキスト

Figma の中核は「複数ユーザーが 1 つのキャンバスを同時編集しても、全員が最終的に同じ状態を見る」こと。本プロジェクトの編集対象は**図形キャンバス**（rect / ellipse / text-label を x/y/w/h/fill/z 等のプロパティで編集、ADR 0002 のデータモデル）。同一オブジェクトの同一プロパティを 2 人が同時に変えたとき、**どう決定的に収束させるか**が最大の論点。

制約:

- **ローカル完結**: 外部 SaaS / マネージド CRDT サービスは使わない。Rails 8 + MySQL + ActionCable で完結させる。
- **既存資産との対比**: `slack` も Rails ActionCable だが、扱うのは append-only メッセージで「順序が多少前後しても各メッセージは独立」。figma は**収束（convergence）が要る**点が本質的に違う。
- **バックエンドは Rails**（言語選定で決定）。Go のような in-memory 単一プロセス権威ではなく、**MySQL を source of truth** にする前提。
- スケール時: 本番では Puma 複数プロセス / 複数ノードに分散する。ActionCable broadcast は Solid Cable（ADR 0003）で跨ぐが、**権威状態は 1 プロセスの memory に置けない**。

「実 Figma は CRDT を使っていない」点も重要な文脈。Figma の公開技術記事では、彼らは pure CRDT（Yjs/Automerge 流）ではなく **server を source of truth とした LWW 風モデル**を採る、と説明している（CRDT のメタデータ肥大・複雑性を、単一権威で順序を裁定することで回避）。本プロジェクトはこの「実プロダクトの判断」を意図的に追体験する。

## 決定

**Server 権威 + per-property LWW-Register（CRDT）** を採用する。

- 編集は **op**（`{object_id, op_type, payload, lamport}`）単位。`payload` は変更プロパティの集合。
- 各プロパティは **LWW-Register**: 値とともに論理時計 `(lamport, actor_id)` を持つ。適用は `(incoming_lamport, actor_id) > stored_clock` のときだけ。tie は `actor_id` で決定的に決める。
- **`deleted` も 1 プロパティ**として LWW で解決（create / update / delete の競合を同一機構に統一）。
- **2 つの時計を分ける**:
  - `lamport`（client 論理時計）= **LWW の勝敗判定**。到着順・server 順に依存しない収束を保証（CRDT 性）。
  - `seq`（server 採番の総順序、ADR 0002）= 配信安定化・catch-up・dedup。**収束の正しさには関与しない**。
- server の権威 = ①`seq` 総順序の採番、②materialized state の durable 保持、③権限検証（viewer の op 拒否）。

## 検討した選択肢

### 1. Server 権威 + LWW-CRDT ← 採用

- 実 Figma の設計思想に最も近い（server source of truth + LWW）。
- LWW-Register は最も単純な CRDT。図形プロパティ（座標・色・サイズ）は「最後の編集が勝つ」で UX 上も自然。
- Rails / MySQL に素直に乗る（per-prop clock を JSON 列で持ち、適用は 1 トランザクション）。

### 2. Pure peer CRDT（Yjs / Automerge 流、server = dumb relay）

- 権威なしで client merge だけで収束する「教科書的 CRDT」。README モチーフ「CRDT」に最も忠実。
- 欠点: server 側で権限検証・スナップショット・lint を効かせにくい（state が client の CRDT 構造に閉じる）。CRDT ライブラリ（外部依存）か自前 RGA 実装が要り、ローカル完結 + Rails の学習主旨から外れる。

### 3. State-based CvRDT（join-semilattice の merge）

- merge の冪等・可換・結合性で収束を証明しやすい。
- 欠点: 状態全体を送る payload が重く、図形キャンバスの低レイテンシ op 配信に向かない。

### 4. OT（Operational Transformation, Google Docs 流）

- テキスト列の同時編集では実績豊富。
- 欠点: 図形プロパティの LWW では transform 関数が過剰。OT は `dropbox`（候補）側で扱い、本リポの「協調 3 流派（CRDT / OT / sync log）」比較の **CRDT 枠を figma が担う**（policy）。

## 採用理由

- **学習価値**: 「server 権威」と「CRDT（LWW）」が**両立する**こと、そして `seq`（順序）と `lamport`（収束）を**分離する**設計を体得できる。実 Figma が pure CRDT を避けた理由を ADR で言語化できる。
- **アーキテクチャ妥当性**: 実プロダクト（Figma）が採る構図。`shopify` の条件付き UPDATE / `uber` の compare-and-set の「状態収束版」として本リポの整合性パターン群に接続する。
- **責務分離**: 収束の正しさは LWW の決定性（client 由来 lamport）に閉じ、server は順序・永続・権限に専念。
- **将来の拡張性**: テキスト共同編集を足すなら、テキスト列だけ sequence CRDT（RGA）に差し替え可能（プロパティ単位 LWW はそのまま）。

## 却下理由

- 案 2（pure peer CRDT）: 権限・snapshot・server-side lint が効かせにくく、外部 CRDT lib 依存か自前 RGA が要る。学習主旨（Rails で server 権威をどう持つか）から逸れる。
- 案 3（CvRDT）: payload が重く低レイテンシ op 配信に不向き。
- 案 4（OT）: 図形プロパティには過剰。CRDT 枠を figma が担うという棲み分け（policy）に反する。

## 引き受けるトレードオフ

- **LWW の「負けた編集は消える」**: 同一プロパティの同時編集は片方が黙って捨てられる（merge ではない）。図形座標では許容（UX 上自然）だが、テキスト本文には不向き → テキストは scope 外（派生で sequence CRDT）。
- **client lamport を信頼**: 悪意ある client が巨大 lamport を送ると常に勝てる。MVP では信頼境界内（認証済み member）に限定。本番では server 側で clamp / 検証（派生 ADR）。
- **server 単一権威の可用性**: server がダウンすると編集確定が止まる（pure peer CRDT ならオフライン継続可）。本リポはローカル完結 MVP なので許容。
- **協調 undo の意味論**: 「自分の op だけ undo」は LWW + 逆 op で近似（高 lamport の逆 op を打つ）。完全な協調 undo は派生 ADR。

## このADRを守るテスト / 実装ポインタ

- `figma/backend/spec/services/operation_applier_spec.rb`（予定）— **収束不変条件**: 同一 op 集合を任意の順序で適用しても materialized `canvas_objects` が同一に収束する（shopify 100-thread / discord race の figma 版）。
- `figma/backend/app/services/operation_applier.rb`（予定）— per-prop `(lamport, actor_id)` 比較 + tie-break。

## 関連 ADR

- ADR 0002: データモデル（op log + materialized state + per-prop clock の格納）
- ADR 0003: リアルタイム配信（ActionCable で op を fan-out、cursor は ephemeral）
- ADR 0004: 認証（member 判定が権限検証の前提）
