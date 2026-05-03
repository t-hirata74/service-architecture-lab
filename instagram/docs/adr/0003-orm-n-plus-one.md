# ADR 0003: Django ORM の N+1 回避と index 設計

## ステータス

Accepted（2026-05-03）

## コンテキスト

Django ORM は **デフォルトが lazy load** で、`for post in posts: post.user.username` のような自然なコードが **N+1 クエリ**になる。Instagram のタイムライン (ADR 0001 fan-out on write) は **1 画面で 20 件 × 各種関連 (作者 / いいね数 / コメント数 / 自分がいいね済みか / メディア)** を引くので、N+1 が発生すると一画面で **数十〜数百 query** に膨らむ。

`github` プロジェクトでは graphql-ruby Dataloader で N+1 を SQL 件数固定にした実装パターンを確立済み ([github/spec/graphql/n_plus_one_spec.rb](../../../github/backend/spec/graphql/n_plus_one_spec.rb))。本プロジェクトでは **Django ORM の標準ツール (`select_related` / `prefetch_related` / `annotate`)** で同等の保証をどう作るかが学習対象。

制約:

- ローカル完結 (django-silk / debug-toolbar は dev 限定で利用)
- 学習対象は **「N+1 を起こさないコードと、それを CI で守る仕組み」** をコードに残すこと
- `assertNumQueries` を pytest fixture から呼んで件数を固定する
- index 設計は **「どのクエリパターンを最適化したか」** が ADR で読めること

## 決定

**「`select_related` / `prefetch_related` / `annotate` を View / Serializer で明示し、`assertNumQueries` で件数を固定する + 必要な複合 index を ADR にリスト化する」** を採用する。

- **list view では必ず prefetch を明示**: `Post.objects.select_related('user').prefetch_related('likes', 'comments')` のように **N+1 が起きうる箇所は serializer ではなく queryset で吸収**
- **counter 系は `annotate(Count(...))`**: `posts.annotate(likes_count=Count('likes'))` でアプリ層 loop を消す
- **`Prefetch` オブジェクトで filter 付きの prefetch**: `Prefetch('likes', queryset=Like.objects.filter(user=request.user), to_attr='liked_by_me')` で「自分がいいねしたか」を 1 query 増やすだけで解決
- **CI で `assertNumQueries`**: list endpoint ごとに `test_timeline_query_count` 等を置き、**件数 = 定数 + log(O(N))** のような期待件数で固定する。後続変更で破綻したら CI が落ちる
- **`django-silk` は dev のみ**: 開発時の query 計測用、production は無効。settings の `DEBUG=True` 時のみ middleware に入れる
- **複合 index は本 ADR にリスト化**: 後述「Index 一覧」セクションで「どの query を狙ったか」を残す

## Index 一覧

| テーブル | index | 狙うクエリ |
| --- | --- | --- |
| `posts` | `(user_id, created_at DESC)` | プロフィール画面 `WHERE user_id=? ORDER BY created_at DESC` |
| `posts` | `(created_at DESC)` (主キー外) | 探索タブ用の最新投稿 fallback |
| `timeline_entries` | `(user_id, created_at DESC)` | タイムライン読み出し (ADR 0001 の主役) |
| `timeline_entries` | `UNIQUE(user_id, post_id)` | fan-out task の冪等化 (ADR 0001) |
| `follow_edges` | PK `(follower_id, followee_id)` | following 列挙 + 重複フォロー防止 |
| `follow_edges` | `(followee_id, follower_id)` | followers 列挙 (fan-out 時) |
| `likes` | `UNIQUE(post_id, user_id)` | いいねの重複防止 + 「自分がいいねしたか」 |
| `likes` | `(post_id)` PK の一部 | post 単位のいいね一覧 |
| `comments` | `(post_id, created_at)` | post 詳細画面のコメント順 |
| `users` | `UNIQUE(username)` | ログイン / プロフィール URL |

## 検討した選択肢

### 1. 明示的 prefetch + `assertNumQueries` ガード ← 採用

- 利点: Django 標準ツールだけで完結、外部 lib 不要
- 利点: queryset を読めば「どの prefetch を意図したか」がコードで読める
- 利点: テストで件数を固定するので、後続変更の N+1 を CI で検知できる
- 欠点: 開発者が `select_related` を忘れると即 N+1。CI ガードがそれを救う

### 2. `django-debug-toolbar` / `silk` を本番にも入れる

- 利点: 全 view の query 件数が観測できる
- 欠点: production overhead が無視できない
- 欠点: テストで固定しないと「観測はできるが回帰検知はできない」

### 3. GraphQL + Dataloader (github 流)

- 利点: field 解決を batch 化することで N+1 を構造的に潰せる
- 欠点: Django + GraphQL (graphene-django) の選択は **本リポの「Django/DRF を学ぶ」目的とズレる**。github プロジェクトで既に graphql-ruby + Dataloader を学習済み
- 欠点: REST + 明示 prefetch の方が **Django の慣習に近い学習対象**

### 4. raw SQL / `cursor.execute`

- 利点: query を 1:1 で書ける、最も速い
- 欠点: ORM の学習対象を捨てる
- 欠点: serializer / form / admin との連携が崩れる

### 5. `iterator()` で memory streaming

- 利点: 大量行を扱うとき memory 効率が良い
- 欠点: list view (20 件 paginate) では効果がない、prefetch が効かない trade-off がある
- 欠点: 本 ADR の論点 (N+1 抑制) と直交

### 6. 1 query で全部書く (denormalize で everything in posts)

- 利点: SELECT 1 発で済む
- 欠点: 更新が複雑、整合性破綻リスク。`likes_count` 程度の denormalize は許すが、コメント本文まで詰めるのは非現実的

## 採用理由

- **学習価値**: Django ORM の `select_related` / `prefetch_related` / `annotate` / `Prefetch` の使い分けを **ADR で意図を残しながらコードに反映**できる。N+1 検知を **`assertNumQueries`** で機械化する設計パターンを確立できる
- **アーキテクチャ妥当性**: Django プロジェクトの実務で最も使われる N+1 抑制パターン。Django の Tutorial / 実書籍でも標準として紹介される
- **責務分離**: queryset レイヤで吸収するので、serializer / view body には N+1 ロジックが漏れない
- **将来の拡張性**: 後で GraphQL を入れたくなったら `graphene-django` の `optimize` を本 ADR の前提に乗せて派生 ADR で扱える

## 却下理由

- **観測のみ (debug-toolbar)**: 検知ではなく観測ツール。回帰検知には不十分
- **GraphQL + Dataloader**: github プロジェクトと学習対象が重複
- **raw SQL**: ORM 学習を捨てる
- **iterator**: 論点が直交
- **強い denormalize**: 整合性管理コストが見合わない

## 引き受けるトレードオフ

- **prefetch 忘れの初動 N+1**: 開発者が `select_related` を書き忘れると一発で N+1。CI の `assertNumQueries` で検知するが、テストを書き忘れた endpoint は素通りする → list endpoint の追加時に **必ず assertNumQueries 試験を 1 本書く**ルールを `docs/coding-rules/python.md` (将来作成) に書く
- **`assertNumQueries` の固定値**: ページネーション件数 / ユーザ数で件数が変動するロジックは固定値で書きづらい。**「N (= page size) によらない固定数」**で書ける形に queryset 側を整理する設計圧として効かせる
- **`Prefetch` の filter 付き prefetch のオーバーヘッド**: 「自分がいいねしたか」を 1 query 増やすが、20 件 list で **N=20 増えず 1 増えるだけ**なので許容
- **counter denormalization (likes_count / comments_count)**: 派生 ADR で扱う余地。本 ADR では `annotate(Count(...))` で都度集計。投稿数 N × likes 平均で重くなるなら denormalize 化する判断を別 ADR に
- **インデックスのカーディナリティ**: `(user_id, created_at)` 複合 index は range scan が効くが、`(created_at)` 単独 index と併存させるとサイズが増える。MVP では併存させ、後で削れる方を観測

## このADRを守るテスト / 実装ポインタ（Phase 2 以降で実装）

- `instagram/backend/posts/views.py` — `select_related('user').prefetch_related('likes', 'comments').annotate(...)` の集約
- `instagram/backend/posts/serializers.py` — `liked_by_me` 等の computed field を queryset 側 prefetch に依存させる
- `instagram/backend/timeline/views.py` — timeline 専用の prefetch
- `instagram/backend/timeline/tests/test_query_count.py` — `assertNumQueries(EXPECTED)` で件数固定
- `instagram/backend/posts/tests/test_query_count.py` — profile 画面 / post 詳細
- `instagram/backend/follows/tests/test_query_count.py` — followers / following 列挙
- `instagram/backend/conftest.py` — `count_queries` fixture (debug 出力)

## 関連 ADR

- ADR 0001: timeline_entries の index は本 ADR の Index 一覧で確定
- ADR 0002: follow_edges の双方向 index は本 ADR の Index 一覧で確定
- ADR 0009 (派生予定): likes_count / comments_count を `posts` に denormalize
- ADR 0010 (派生予定): 全文検索 (MySQL FULLTEXT ngram) for caption / username
