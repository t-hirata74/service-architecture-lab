# ADR 0003: Hot ランキングアルゴリズムと再計算バッチ (ai-worker)

## ステータス

Accepted（2026-05-04）

## コンテキスト

Reddit のフロントページ / サブレディットの並びは **Hot / Top / New / Best** の 4 つが代表的。本プロジェクトの中核学習対象である **「ランキングを backend と ai-worker でどう分業するか」** を扱うため、まず **Hot** を一級扱いで実装する (Top / New は単純な ORDER BY で済むので副次扱い)。

Reddit の **Hot 算出式** (Amir Salihefendić による有名実装):

```
score = log10(max(|s|, 1)) * sign(s) + (epoch_seconds - 1134028003) / 45000
where s = ups - downs
```

- 第 1 項: 票差を log スケールで効かせる (1 票差と 100 票差を線形差にしない)
- 第 2 項: 経過時間で底上げする (新しいほど有利)。`45000 秒 ≒ 12.5 時間` が「2 倍効く」のスケール
- `1134028003` は 2005-12-08 の epoch (Reddit 上場前のサービス開始時点の固定オフセット)

論点:

- **どこで計算するか**: backend (FastAPI) のリクエスト時 / ai-worker のバッチ / DB の generated column / クライアント
- **いつ更新するか**: 投票のたび / 一定間隔のバッチ / 読み取り時オンザフライ
- **何に保持するか**: `posts.hot_score FLOAT` を持って ORDER BY / ranking 専用テーブル / インデックス vs sort

ローカル制約:

- ローカル完結 (MySQL + FastAPI + ai-worker)
- ai-worker (FastAPI) は instagram と同様に **「Python ワーカーの責務分離」** を体感する場
- 「投票のたびに ranking を再計算」は backend を ranking 計算でブロックさせるのでやらない (slack / youtube の AI 境界と同じ規律)

## 決定

**「Hot スコアは `posts.hot_score FLOAT` に denormalize し、ai-worker の定期バッチ (60 秒間隔) で再計算する。再計算対象は `updated_at` が直近 24 時間以内 or `score` が変化した post のみ」** を採用する。

- スキーマ:
  - `posts.hot_score FLOAT NOT NULL DEFAULT 0`
  - `posts.hot_recomputed_at DATETIME NULL`
  - INDEX `(subreddit_id, hot_score DESC, id DESC)` でサブレディット内 Hot 並び
- 計算式:
  - Reddit Hot 式をそのまま `ai-worker/app/ranking/hot.py` に Python で実装
  - `score = ups - downs` を `posts.score` から直接使う (ADR 0002 の denormalize)
- 実行モデル:
  - **ai-worker 内に APScheduler の interval ジョブ** (60 秒) を立て、`recompute_hot_scores` を回す
  - クエリ: `SELECT id, score, created_at FROM posts WHERE deleted_at IS NULL AND created_at > NOW() - INTERVAL 7 DAY` で **直近 7 日分のみ対象** (古い post は Hot にほぼ影響しない)
  - **bulk UPDATE**: 全 post を Python 側で計算 → `INSERT ... ON DUPLICATE KEY UPDATE hot_score = VALUES(hot_score)` か `executemany` で書き戻し
- API:
  - backend `/r/{subreddit}/hot` は **`SELECT * FROM posts WHERE subreddit_id = ? ORDER BY hot_score DESC LIMIT 25`**
  - 60 秒以内のラグは仕様として受容 (UI に「並び順は約 1 分ごとに更新されます」とは出さない)
- 即時反映の例外:
  - **新規 post 投稿時**: backend 側で **同期的に hot_score の初期値を計算してから INSERT** (バッチ待ちで「自分の post が一覧に出てこない」UX 破綻を避ける)
  - **派生 ADR 候補**: 投票のたびに hot を即時計算する best-effort 経路

## 検討した選択肢

### 1. ai-worker 60s バッチ + denormalize ← 採用

- 利点: backend は ORDER BY 一発で OK、ranking 計算で詰まらない
- 利点: 「ai-worker の責務 = 計算系の重い処理」という本リポ全体の規律と整合
- 利点: バッチ間隔 (60s) は ADR で動かせる定数。学習論点として「60s と 5s でどうトレードオフするか」を残せる
- 欠点: 60s ラグ → MVP として許容

### 2. backend のリクエスト時にオンザフライ計算

- 利点: 完全に最新
- 欠点: 一覧 25 件 × 計算式 を毎リクエストで実行。負荷集中 / N+1 / index が効かない (ORDER BY の対象が SQL 関数になる)
- 欠点: 学習論点として ai-worker を使う必然性が消える

### 3. 投票のたびに hot を即時更新 (backend 内で ADR 0002 と同居)

- 利点: ラグなし
- 欠点: 投票トランザクションに ranking 計算が乗り、人気 post で詰まる
- 欠点: ranking 計算ロジックが backend と ai-worker で二重持ちになる

### 4. MySQL の generated column / view

- 利点: SQL だけで完結
- 欠点: MySQL の generated column で `LOG10` + `EPOCH` を使うのは可能だが、**index を ranked column に張れない** (式 index に制約) → ORDER BY hot_score の高速化が望めない
- 欠点: 学習論点 (Python での計算 / ai-worker との分業) を捨てる

### 5. ranking 専用テーブル `post_rankings`

- 利点: posts のスキーマを汚さない
- 欠点: 既存 `posts` への JOIN が常時必要、index 設計が増える割に得るものが少ない
- 欠点: posts.score を見るのと変わらない (どうせ denormalize)

## 採用理由

- **学習価値**: 「Reddit Hot 式を **ai-worker の Python で実装** + backend は ORDER BY だけ」という **責務の分離**を明確に示せる。perplexity / instagram の ai-worker 規律と同形
- **performance**: ORDER BY hot_score + 複合 index で 25 件取得が一定時間で済む
- **拡張余地**: 第 2 項のスケール (45000 秒) を変える / weight を sub ごとに変える / 「Best (Wilson 信頼区間)」を追加、いずれも ai-worker 内に閉じる
- **対比可能性**: youtube の Solid Queue (Rails 内) / instagram の Celery worker / discord の goroutine と並べて **「ranking バッチを ai-worker (FastAPI scheduler) でやる」** を 4 種類目の非同期パターンとして残せる

## 却下理由

- **オンザフライ**: 性能 / 学習論点の両方で劣る
- **投票同期**: トランザクション膨張 / ロジック二重持ち
- **generated column**: index と Python コーディングの両方を捨てる
- **専用テーブル**: 得るものが薄い

## 引き受けるトレードオフ

- **60 秒ラグ**: 投票が反映されるまで最大 60 秒。新規投稿の初期値だけ同期計算で逃がす
- **drift と reconcile**: ADR 0002 の reconcile job と同居。同じ ai-worker プロセスで `posts.score` の整合 → `hot_score` 再計算の順序で実行
- **ai-worker 障害時**: hot_score が更新されなくなる → 「**並び順が古いまま**」だけで API 自体は動く (graceful degradation、operating-patterns §2 と整合)
- **scheduler の重複起動**: ai-worker を複数台起動すると重複バッチが走る。MVP は **single instance 前提** (派生 ADR で advisory lock / 専用 worker 化)
- **計算窓 (7 日)**: 古い post は hot 順位が事実上 0 → 7 日窓は割り切り。Reddit のように長期記事 (年 1 で再浮上) を扱うには窓を広げる必要があるが MVP では不要
- **`hot_score FLOAT` の精度**: float の単精度で十分。順序保存しか使わないので絶対値の精度は不要

## このADRを守るテスト / 実装ポインタ（Phase 2 以降で実装）

- `reddit/ai-worker/app/ranking/hot.py` — `def hot(score: int, created_at: datetime) -> float`
- `reddit/ai-worker/app/ranking/scheduler.py` — APScheduler interval 60s で `recompute_hot_scores`
- `reddit/ai-worker/tests/test_hot_formula.py` — 既知のサンプル (Reddit のリファレンス実装と一致)
- `reddit/ai-worker/tests/test_recompute_batch.py` — bulk UPDATE が走り、posts.hot_score が反映される
- `reddit/backend/app/domain/posts/repository.py` — `list_hot(subreddit_id, limit)` は `ORDER BY hot_score DESC, id DESC LIMIT ?`
- `reddit/backend/app/domain/posts/service.py` — `create_post` で初期 hot_score を **同期計算**してから INSERT
- `reddit/backend/tests/posts/test_hot_initial.py` — 新規投稿が即座に一覧に出る (initial hot_score がゼロでない)

## 関連 ADR

- ADR 0001: コメントツリー (post 内のコメントは hot ではなく score / Best ソート)
- ADR 0002: 投票の整合性 (`posts.score` がこの ADR の入力)
- ADR 0004: 認証方式 (Hot 一覧は anonymous 可、`/me` は要 token)
- ADR 0005 (派生予定): Best (Wilson 信頼区間) の追加 / コメントの Best 順
- ADR 0006 (派生予定): scheduler の advisory lock + 複数台耐性
- ADR 0007 (派生予定): 投票即時の best-effort hot 更新
