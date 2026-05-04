# ADR 0002: 投票 (vote) の整合性と score の denormalize

## ステータス

Accepted（2026-05-04）

## コンテキスト

`reddit` の投票 (upvote / downvote) は **「ユーザ × 投稿 (or コメント) の状態を 3 値 (`+1 / 0 / -1`) で永続化し、その合計値を post / comment の score として表示する」** 機能。

ドメイン特性:

- ユーザは同じ post に **何度でも投票切り替えができる** (up → down → 取消、など)
- 「同じ post に同じユーザが二重に +1」を絶対に許さない (整合性が UX に直結する)
- score は **ランキング (Hot / Top / Best、ADR 0003) の入力**になるので、**読み取りが極端に多い** (タイムラインの全カードで score を見る)
- 投票自体はそこまで頻繁ではないが、人気 post で「同時に複数ユーザが投票」は普通に起きる

選択肢の軸は 2 つ:

- **A. truth の置き場所**: votes テーブルだけが truth / posts.score も truth (denormalized)
- **B. 加算方法**: 都度 `SELECT SUM` / `UPDATE ... SET score = score + delta` (relative) / `UPDATE ... SET score = ?` (absolute)

制約:

- ローカル完結 (MySQL 8 + SQLAlchemy async)
- 「投票の整合性」を学習論点として **コードから読み取れる**形にしたい
- ai-worker のランキングバッチ (ADR 0003) は post の score を直接読む

## 決定

**「votes テーブルを truth とし、posts.score を denormalized cache として持つ。書き込みは MySQL の `INSERT ... ON DUPLICATE KEY UPDATE` で投票行を upsert し、同一トランザクション内で `UPDATE posts SET score = score + ?` を相対更新で当てる」** を採用する。

- スキーマ:
  - `votes (user_id, target_type ENUM('post','comment'), target_id, value TINYINT, created_at, updated_at)` で `UNIQUE(user_id, target_type, target_id)`
  - `posts.score INT NOT NULL DEFAULT 0`
  - `comments.score INT NOT NULL DEFAULT 0`
- フロー (post に upvote する場合):
  1. トランザクション開始
  2. 既存の `votes` 行を `SELECT ... FOR UPDATE` で取得 (なければ `value = 0` 扱い)
  3. `delta = new_value - old_value` を計算 (例: 0→1 なら +1、-1→1 なら +2)
  4. `INSERT ... ON DUPLICATE KEY UPDATE value = ?, updated_at = NOW()` で upsert
  5. `UPDATE posts SET score = score + :delta WHERE id = :post_id`
  6. コミット
- **取消** (`value = 0`): `votes` 行は **物理削除せず `value = 0` を保持**する。理由は「**過去に投票したかどうか**」を保持する (将来 audit / undo 操作の余地)
- **不整合検出**: 別途 `ai-worker` で **「votes から SUM(value) を再計算して posts.score と diff を取る reconcile job」** を持つ (ADR 0003 の Hot 再計算と同居)。MVP では nightly 実行を想定し、`drift > 0` のものをログ出力するだけ
- **`SELECT FOR UPDATE` の対象**: votes 行のみ (post 行はロックしない)。post 行は `UPDATE ... SET score = score + delta` の **行ロックのみで OK** (絶対値計算ではないので順序依存しない)

## 検討した選択肢

### 1. votes truth + posts.score denormalize, 相対更新 ← 採用

- 利点: 投票は **`votes` の upsert 1 回 + `posts` の相対加算 1 回**で済む
- 利点: 相対加算 (`SET score = score + delta`) なので、**並行 UPDATE が同じ行に来ても結果が正しい** (絶対値書き込みのような race を起こさない)
- 利点: 「votes が truth、score は cache」という責務分離が明確
- 欠点: `posts.score` が drift する余地がある → reconcile job で吸収

### 2. votes truth + posts.score を都度 SUM 計算

- 利点: 整合性が完璧 (絶対に drift しない)
- 欠点: タイムライン表示で **「全 post に対して `SELECT SUM(value) FROM votes WHERE post_id = ?`」** を打つことになり、N+1 / 巨大 join のどちらかで詰む
- 欠点: ランキング計算 (Hot) を ai-worker で回すたびに全 votes をスキャンする必要がある
- 欠点: 学習論点 (denormalize と reconcile) を捨てる

### 3. posts.score だけ truth (votes テーブルなし)

- 利点: 最小スキーマ
- 欠点: 「同じユーザの二重投票」を防ぐ手段がない (UNIQUE 制約をかける対象がない)
- 欠点: 「投票切り替え」が成立しない (差分計算ができない)

### 4. 絶対値書き込み (`UPDATE posts SET score = (SELECT SUM ...) WHERE id = ?`)

- 利点: drift しない
- 欠点: **race condition**。2 ユーザが同時に投票して `SELECT SUM` のスナップショットが古いと、後勝ちで片方の票が消える
- 欠点: 解決には post 行を pessimistic lock する必要があり、人気 post のスループットが落ちる

### 5. votes 行を物理削除 (取消時)

- 利点: ストレージが小さくて済む
- 欠点: 「過去に投票したかどうか」が分からなくなり、将来の audit / undo / vote history 表示で困る
- 欠点: 物理削除と相対加算を組み合わせると **「DELETE 後にもう一度 INSERT」** で UNIQUE 制約に当たるリスクが残る (ON DUPLICATE KEY UPDATE で済ませるほうが扱いが軽い)

## 採用理由

- **整合性の論点をコードから読み取れる**: `votes` upsert + `posts` 相対加算の 2 ステップが 1 トランザクションに収まっており、「**race / drift / reconcile**」という 3 つの言葉を **コードで体感できる** 配置になっている
- **相対加算は並行 UPDATE に強い**: 単純で最も性能が出る。Reddit 的に投票が同じ post に集中することへの自然な答え
- **ランキング (ADR 0003) との接合が良い**: ai-worker は `posts.score` を直接読めば良く、毎回 SUM を取らなくて済む
- **責務分離**: 「truth = votes、cache = posts.score、整合性は reconcile job が保証」 という 3 役の分業がそのまま ADR 0003 のバッチ設計に繋がる

## 却下理由

- **都度 SUM**: 性能が出ない & ランキング側で破綻する
- **votes 不在**: 二重投票防止ができない (UNIQUE をかける場所がない)
- **絶対値書き込み**: race condition が発生し、人気 post で票が消える可能性

## 引き受けるトレードオフ

- **drift の可能性**: クラッシュ / 部分失敗で `votes` と `posts.score` がズレる。**reconcile job** (ai-worker から) で nightly に修正
- **votes 行は永続**: 取消後も行が残るのでストレージが線形増。MVP では許容、派生 ADR で「N 日後に value=0 行を archive」
- **post 行ロックの集中**: 人気 post で `UPDATE ... SET score = score + ?` が直列化される。MVP では許容。派生 ADR で「buffered increment (Redis INCR + nightly flush)」
- **closure ordering**: votes upsert と posts 加算の順序を逆にすると、トランザクション abort 時に votes だけ残って score 加算されない事象が考えうる。実装では **votes upsert → posts 加算 → COMMIT** の固定順
- **`value = 0` の意味論**: アプリ層では `value = 0` を「中立 / 取消」と解釈。ランキング SUM では効果なし、UNIQUE 制約には引き続き寄与

## このADRを守るテスト / 実装ポインタ（Phase 2 以降で実装）

- `reddit/backend/app/domain/votes/service.py` — `cast_vote(user_id, target_type, target_id, value)` (-1 / 0 / +1)
- `reddit/backend/migrations/0003_create_votes.py` — `votes` + UNIQUE(user_id, target_type, target_id)
- `reddit/backend/tests/votes/test_toggle.py` — 0→+1→-1→0 で `posts.score` が `+1, -2, +1` と変化、最終 0 に戻る
- `reddit/backend/tests/votes/test_concurrent.py` — 2 ユーザが同時に +1 で score が 2 になる (相対加算の race-free)
- `reddit/backend/tests/votes/test_idempotent.py` — 同じ value で 2 回投票しても score が二重加算されない (`delta = new - old = 0`)
- `reddit/ai-worker/app/jobs/reconcile_score.py` — votes SUM と posts.score を比較し drift をログ
- `reddit/ai-worker/tests/test_reconcile.py` — 意図的に drift を起こして検出

## 関連 ADR

- ADR 0001: コメントツリー (`comments.score` も同じ仕組みで denormalize)
- ADR 0003: Hot ランキング (この ADR の `posts.score` を入力にする)
- ADR 0004: 認証方式 (投票には認証が必須)
- ADR 0005 (派生予定): buffered increment (Redis INCR + nightly flush) で人気 post のロック集中を緩和
- ADR 0006 (派生予定): votes 行の archive と vote history API
