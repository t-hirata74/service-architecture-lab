# ADR 0002: フォローグラフの DB 設計

## ステータス

Accepted（2026-05-03）

## コンテキスト

フォロー関係は **有向グラフ (A が B をフォローしている ≠ B が A をフォロー)** で、Instagram のドメインの中核を成す。タイムライン生成 (ADR 0001 fan-out on write) では「投稿者をフォローしている人 = followers」を引き、プロフィール表示では「自分がフォローしている人 = following」を引くので、**双方向クエリの両方が頻出**する。

制約:

- ローカル完結 (MySQL のみ、Neo4j 等のグラフ DB は使わない)
- ローカル MVP のスケール想定 (フォロー数 ≤ 数千 / ユーザ)。本物の Instagram スケール (数億エッジ) はスコープ外
- 学習対象は **「ある選択肢を採れば何が見えなくなるか」** を ADR で残すこと。「Neo4j を採らなかった」「matrix を採らなかった」を明示的に書く
- denormalize した counter (`followers_count` / `following_count`) はプロフィール画面で必須 → 同 ADR で扱う

## 決定

**「Adjacency List 型の `follow_edges` テーブル + 双方向 index + denormalized counter」** を採用する。

- **`follow_edges (follower_id, followee_id, created_at)`** 単一テーブル
- **PK = `(follower_id, followee_id)`** 複合 (重複フォロー防止 + following 列挙の高速化)
- **逆引き index `(followee_id, follower_id)`** を別途定義 (followers 列挙の高速化)
- **denormalized counter**: `users.followers_count` / `users.following_count` を保持し、`Follow` の create/destroy signal で `F('count') + 1` / `- 1` で更新 (race condition 回避)
- **soft delete はしない**: `unfollow` は物理 DELETE。「過去にフォローしていた」を残す要件は無い (block 機能は別テーブルで設計予定 / 本 ADR スコープ外)
- **block / 非公開アカウント**: 派生 ADR で扱う。本 ADR は **公開アカウント間の片方向 follow** のみ

## 検討した選択肢

### 1. Adjacency List + 双方向 index + denormalized counter ← 採用

- 利点: PK と secondary index で **followers / following の両方向**が O(log N) で引ける
- 利点: フォロー / アンフォローが INSERT / DELETE 1 行で済む
- 利点: counter は denormalize で `SELECT COUNT(*)` を回避
- 欠点: 2-hop クエリ (FoF 推薦) は self-join になり、N+1 が出やすい → ADR 0003 で対処

### 2. Adjacency Matrix (`follows[user_id][followee_id]` 想定)

- 利点: 隣接判定が O(1) (matrix lookup)
- 欠点: ユーザ数 N で **メモリ O(N²)**。MVP でも 1000 ユーザ × 1000 = 1M セルでメモリ非効率、現実的でない
- 欠点: RDB に展開する形がそもそも無理筋 (sparse な matrix を縦持ちするなら Adjacency List と同じ)

### 3. Closure Table (祖先・子孫を全列挙)

- 利点: N-hop の祖先 / 子孫検索が高速
- 欠点: フォローグラフは **DAG ではなくサイクルあり** (A→B→A の相互フォローは普通)。Closure Table はサイクル前提でない
- 欠点: フォロー / アンフォロー時に `O(関係数²)` で更新が必要、書き込み爆発

### 4. グラフ DB (Neo4j / Amazon Neptune)

- 利点: 「友達の友達」「相互フォローのみ抽出」等の path query が SQL より自然 (Cypher)
- 利点: 大規模スケール時に強い
- 欠点: **本リポの「ローカル完結 / MySQL 中心」の方針から外れる**。Neo4j を立てると docker-compose の依存が増え、Django ORM の学習対象から逸れる
- 欠点: 学習対象を「グラフ DB」と「Django ORM N+1」の二つに分散させると、各論点が薄くなる

### 5. denormalize counter を使わない (毎回 `COUNT(*)`)

- 利点: 整合性管理がいらない (常に SELECT で正解)
- 欠点: プロフィール画面ごとに `SELECT COUNT(*)` × 2 が走る。フォロー数 数千でも遅い
- 欠点: caching layer を別途用意する必要が出てくる (本末転倒)

### 6. counter を Redis でカウントする

- 利点: Redis INCR で原子的、超高速
- 欠点: **MySQL の users 行と Redis counter の二系統永続化**になり、整合性管理が二重化する
- 欠点: 派生 ADR で「Redis を taglevel cache に使う」と決めたタイミングで再検討する余地は残す

## 採用理由

- **学習価値**: Django ORM (`F` 式 / `unique_together` / `db_index` / `Meta.indexes`) と `Follow.objects.create` / `delete` 周りの実務感が一気に揃う。RDB で双方向グラフを扱う常套手段
- **アーキテクチャ妥当性**: 実 Twitter / Instagram も初期は Adjacency List で実装していたことが知られる (現在は分散 KV だが論理構造は同じ)
- **責務分離**: counter 更新は signal に閉じ込める。view / service 層で counter を意識する必要がない
- **将来の拡張性**: block / mute / 非公開アカウント / フォロー request はすべて `follow_edges` に列を増やすか、別テーブルを足す形で対応できる

## 却下理由

- **Adjacency Matrix**: メモリ非効率、RDB 形に乗らない
- **Closure Table**: サイクル前提でない、書き込み爆発
- **グラフ DB**: 本リポ方針 (MySQL only / Django ORM 学習) から外れる
- **counter なし**: プロフィール画面の体感速度が出ない
- **Redis counter**: 永続化二系統で整合性管理が膨らむ。派生 ADR で再検討余地

## 引き受けるトレードオフ

- **counter の整合性**: signal が落ちると counter がズレる。`F('count') + 1` で race condition は回避できるが、signal 例外時はズレる。**夜間 batch で `SELECT COUNT(*)` から修復**するメンテナンスタスクを `manage.py recount_follows` として用意 (Phase 2 で実装)
- **2-hop クエリの N+1**: 「フォローしている人がフォローしている人 (FoF)」を取るとき、素朴に書くと N+1 が出る。ADR 0003 で `prefetch_related` 戦略として吸収
- **追加列の拡張**: block / mute を追加するとき `follow_edges` に列を増やすか別テーブルにするかの判断が発生する。本 ADR では **「`follow_edges` は follow 関係のみ、block は別テーブル」** と方針だけ示し、詳細は派生 ADR で
- **storage**: フォロー数の総和に線形。1M ユーザ × 平均 100 フォロー = 100M 行は MySQL でも捌けるサイズ。スケール時は **shard 分割の余地は残す** が本 ADR スコープ外
- **non-public アカウント**: 本 ADR は公開のみ。非公開を入れるなら `follow_requests` テーブルを別途作り、`accept` で `follow_edges` に昇格させる流れ → 派生 ADR で

## このADRを守るテスト / 実装ポインタ（Phase 2 以降で実装）

- `instagram/backend/follows/models.py` — `Follow` モデル (PK + reverse index + counter signal)
- `instagram/backend/follows/signals.py` — `post_save` / `post_delete` で `F('followers_count') ± 1`
- `instagram/backend/follows/tests/test_indexes.py` — `assertNumQueries(1)` で双方向検索が 1 query
- `instagram/backend/follows/tests/test_counter.py` — create / delete で counter が +1 / -1
- `instagram/backend/follows/tests/test_unique.py` — 同じ (follower, followee) ペアの重複 create が IntegrityError
- `instagram/backend/management/commands/recount_follows.py` — 夜間整合性修復コマンド

## 関連 ADR

- ADR 0001: タイムライン生成 (follower 一覧を fan-out で使う側)
- ADR 0003: Django ORM N+1 (双方向 index + prefetch_related)
- ADR 0007 (派生予定): block / mute / 非公開アカウント
- ADR 0008 (派生予定): Redis cache for hot follower lists
