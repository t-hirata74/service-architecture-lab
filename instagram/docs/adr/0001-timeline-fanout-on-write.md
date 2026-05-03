# ADR 0001: タイムライン生成戦略 (fan-out on write)

## ステータス

Accepted（2026-05-03）

## コンテキスト

`instagram` プロジェクトの中核技術課題は **「フォロー中ユーザの投稿を時系列順に並べたタイムラインを生成する」** こと。これはサービスの性質上、**read が write より圧倒的に多い** (タイムラインは投稿のたびではなく開くたびに見られる) という非対称性がある。

タイムライン生成方式は概念的に 2 つに分かれる:

- **push 型 (fan-out on write)**: 投稿時に **フォロワー全員のタイムラインに事前展開**しておき、read は単一テーブルの index scan で済ませる
- **pull 型 (fan-out on read)**: 投稿はそのまま `posts` に書くだけ。read 時に **フォロー中ユーザ全員の投稿を JOIN/IN で集約**する

実 Instagram は push 型を主軸にしつつ、フォロワー数が多いアカウント (celebrity) のみ pull に切り替える hybrid を採用していることが知られている (Cassandra ベースの timeline service)。

制約:

- ローカル完結 (MySQL + Redis のみ、Cassandra や DynamoDB は使わない)
- 学習対象は **「タイムライン生成の write/read 非対称性」** をコードで体感すること
- 非同期ワーカーの実務感 (Celery + Redis) を Django の文脈で獲得したい
- Phase 1 で celebrity 問題まで含めると ADR が膨らみすぎる → 派生 ADR で扱う

## 決定

**「fan-out on write を Celery + Redis で非同期実行し、`timeline_entries` テーブルに事前展開する」** を採用する。

- **`Post` 作成時** に Django signal (`post_save`) で Celery task `fanout_post_to_followers` を enqueue
- **Celery worker** が `follow_edges` を引いてフォロワー一覧を取得し、`timeline_entries (user_id, post_id, created_at)` に **bulk_create** で挿入
- **タイムライン読み出し**: `SELECT post_id FROM timeline_entries WHERE user_id = ? ORDER BY created_at DESC LIMIT 20` の単一 index scan + `Post` の prefetch
- **削除**: `Post.delete()` 時にも signal で fan-out 削除タスクを enqueue (フォロワーの timeline から該当 entry を消す)
- **新規 follow 時の backfill**: `Follow` 作成時に「対象ユーザの直近 N 件の投稿」を新フォロワーの `timeline_entries` に挿入 (タイムラインが空にならないため)
- **ベンチ規模**: MVP では 1 投稿あたりフォロワー数 ≤ 数百を想定。celebrity (>10K) 問題は **派生 ADR で hybrid 化** する余地として残す

## 検討した選択肢

### 1. fan-out on write (push) ← 採用

- 利点: read が単一 table の index scan で完結し、`SELECT ... ORDER BY created_at DESC` がそのまま使える
- 利点: read latency が予測可能 (フォロー数に依存しない)
- 利点: Celery + Redis + Django signal という Django/Python 実務スタックが学習対象として揃う
- 欠点: write amplification (1 投稿 = N 行挿入)。celebrity で破綻する → 派生 ADR で hybrid 化
- 欠点: ストレージコスト (timeline_entries が `posts × フォロワー平均数` で増える)

### 2. fan-out on read (pull)

- 利点: write が安い (`posts` への INSERT 1 件のみ)
- 利点: ストレージが線形 (timeline 専用テーブル不要)
- 欠点: read 時に `SELECT * FROM posts WHERE user_id IN (followee_ids) ORDER BY created_at DESC LIMIT 20` で **巨大 IN 句 + 大規模 sort** が発生する。フォロー数が増えると劣化
- 欠点: read が遅延すると体感品質に直撃する (タイムラインは UI のメイン画面)
- 欠点: index 設計が苦しい (`posts (user_id, created_at)` 複合 index で IN scan + merge sort になる)

### 3. hybrid (push + pull, celebrity だけ pull)

- 利点: 実 Instagram に最も近い、push の write amplification を celebrity でだけ回避
- 欠点: 実装が複雑 (read 時に「pull するアカウント集合」を別管理する必要がある)
- 欠点: Phase 1 で取り入れると ADR 1 本が膨らむ。**push を実装した後に派生 ADR で追加**するのが学習上自然

### 4. 同期 fan-out (Celery を使わず view 内で展開)

- 利点: Celery / Redis を入れなくて済む
- 欠点: フォロワー 1000 人で 1000 行 INSERT が **API レスポンスを直接ブロック**する (UX 破綻)
- 欠点: 「非同期ワーカーを Django で扱う」という学習対象を捨てる

### 5. キャッシュレイヤー (Redis ZSET でタイムライン保持)

- 利点: 読み取りが O(log N) Redis 操作で完結、メモリ局所性が高い
- 欠点: 永続化が二系統 (MySQL truth + Redis cache) になり、整合性管理コストが増える
- 欠点: MVP のスコープを超える。**派生 ADR で「ホットユーザの timeline を Redis ZSET にキャッシュ」**として追加余地

## 採用理由

- **学習価値**: Django signal + Celery worker + bulk_create + 非同期ワーカーの状態管理という Django/Python 実務スタックが一気に揃う。slack (Rails ActionCable) や youtube (Solid Queue) との **「非同期ワーカーの実装比較」** が学習素材になる
- **アーキテクチャ妥当性**: 実 Twitter / Instagram の初期設計に近い。push を理解していなければ hybrid も理解できない
- **責務分離**: Django signal は薄い trigger 層、実体は Celery task に逃がす。view は同期 INSERT のみ
- **将来の拡張性**: celebrity 用 pull 切替 / Redis ZSET キャッシュ / fan-out の冪等化、いずれも push 実装の上に派生 ADR として積める

## 却下理由

- **pull 型**: read latency が follow 数に依存し、UI 体験を直撃する。学習として「事前計算」のメリットを体感できない
- **hybrid**: 初手で複雑度が高すぎる。push 実装後に派生 ADR として追加する方が学習順序として自然
- **同期 fan-out**: 非同期ワーカーの学習を捨てる、本リポの ai-worker 文化とも整合しない
- **Redis ZSET**: 永続化が二系統になり、初期 ADR で扱うには論点が広い

## 引き受けるトレードオフ

- **write amplification**: 1 投稿 N 行 INSERT。celebrity で破綻するが、MVP スコープでは許容。`UserStats` で `followers_count` を持ち、`>= 10000` のとき警告ログを出す監視ガードのみ入れる
- **eventual consistency**: 投稿後に Celery が走り終わるまでは follower のタイムラインに現れない (秒オーダーの遅延)。投稿者本人のタイムラインにだけ同期 INSERT する例外を入れる (`timeline_entries` に self entry を直接 INSERT) ことで「自分の投稿は即座に見える」UX を保つ
- **削除の遅延**: Post 削除時の fan-out 削除も非同期。削除されるまで follower のタイムラインに残る → read 時に `Post` を `prefetch_related` で取得し、`deleted_at IS NOT NULL` のものは表示時にフィルタ
- **storage**: `timeline_entries` が `posts × avg_followers` で線形に増加。MVP では TTL や圧縮を入れない。派生 ADR で「N 日経過した entry を archive table に move」を扱える
- **冪等性**: Celery task は at-least-once。`UNIQUE (user_id, post_id)` を `timeline_entries` に張り、`INSERT IGNORE` で重複を吸収
- **新規フォロー時の backfill 範囲**: 直近 20 件のみ。古い投稿を遡るには pull 経路を別途用意する必要があるが MVP では未対応 (派生 ADR)

## このADRを守るテスト / 実装ポインタ（Phase 2 以降で実装）

- `instagram/backend/posts/models.py` — `Post` モデル + `post_save` signal
- `instagram/backend/timeline/models.py` — `TimelineEntry` モデル (`user_id`, `post_id`, `created_at`, `UNIQUE(user_id, post_id)`)
- `instagram/backend/timeline/tasks.py` — `fanout_post_to_followers` Celery task
- `instagram/backend/timeline/views.py` — `GET /timeline` (cursor pagination)
- `instagram/backend/timeline/tests/test_fanout.py` — フォロワー全員に entry が作られる
- `instagram/backend/timeline/tests/test_self_visibility.py` — 投稿者本人は同期 INSERT で即座に見える
- `instagram/backend/timeline/tests/test_idempotent.py` — task の重複実行で重複 INSERT が起きない

## 関連 ADR

- ADR 0002: フォローグラフの DB 設計 (fan-out 時に follower 一覧を引く側)
- ADR 0003: Django ORM N+1 と index 設計 (`timeline_entries` の index と `Post` prefetch)
- ADR 0004: 認証方式 (timeline は owner のみ)
- ADR 0005 (派生予定): hybrid push/pull (celebrity 対応)
- ADR 0006 (派生予定): timeline cache layer (Redis ZSET)
