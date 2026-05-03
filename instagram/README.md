# Instagram 風タイムライン (Django/DRF)

Instagram のアーキテクチャを参考に、**「フォロー中ユーザの投稿を、タイムライン上で時系列順に表示する」** をローカル環境で再現するプロジェクト。

slack (Rails / WebSocket fan-out) / youtube (Rails / Solid Queue 状態機械) / github (Rails / GraphQL + 権限グラフ) / perplexity (Rails / SSE + RAG) に続く 5 つ目のプロジェクトとして、**バックエンドを意図的に Django/DRF + Celery + Python に切り替え** ([CLAUDE.md「言語別プロジェクト」](../CLAUDE.md#学習方針言語別プロジェクトと-rails-リプレイス)) し、**タイムライン生成戦略 / フォローグラフ DB 設計 / Django ORM N+1 / 非同期 fan-out worker** の 4 つを正面から扱う。

外部 SaaS / LLM / 画像認識 API は使用せず、ai-worker 側で deterministic な mock を実装することでローカル完結を保つ。

---

## 見どころハイライト (設計フェーズ)

> Phase 1 完了時点。実装は Phase 2 以降で進める。

- **fan-out on write を Celery で非同期実行** — `Post` 作成時に signal で Celery task を enqueue、フォロワー全員の `timeline_entries` に bulk_create。read は単一 index scan で完結 ([ADR 0001](docs/adr/0001-timeline-fanout-on-write.md))
- **Adjacency List + 双方向 index + denormalized counter** — `follow_edges` 単一テーブルで followers / following を両方向 index で引き、`F('count') ± 1` で counter を更新 ([ADR 0002](docs/adr/0002-follow-graph.md))
- **`select_related` / `prefetch_related` / `annotate` + `assertNumQueries` で N+1 を CI で固定** — Django ORM 標準ツールだけで N+1 を抑制し、テストで件数を期待値に固定 ([ADR 0003](docs/adr/0003-orm-n-plus-one.md))
- **DRF TokenAuthentication で 1 経路** — `Authorization: Token <token>` ヘッダ、CSRF 不要、SPA との相性が良い。perplexity (rodauth-rails JWT bearer) との **「Rails ↔ Django で同じ役割をどう実装するか」** の対比 ([ADR 0004](docs/adr/0004-auth-drf-token.md))

---

## アーキテクチャ概要

```mermaid
flowchart LR
  user([User Browser])
  user -->|HTTPS / fetch| front[Next.js 16<br/>:3045]
  front -->|REST<br/>Authorization: Token| api[Django + DRF<br/>:3050]
  api <-->|REST<br/>POST /recommend<br/>POST /tags| ai[FastAPI ai-worker<br/>:8040]
  api --> celery[Celery worker]
  celery --- redis[(Redis 7<br/>:6380)]
  api --- redis
  api --- mysql[(MySQL 8<br/>:3311)]
  celery --- mysql
  ai --- mysql
```

詳細な ER / fan-out シーケンス / index 一覧は **[docs/architecture.md](docs/architecture.md)** を参照。

---

## 採用したスコープ

| 含める | 除外 |
| --- | --- |
| ユーザ / フォロー (有向グラフ) | 非公開アカウント / フォロー request / block / mute |
| 投稿 (caption + image_url) / いいね / コメント | 画像本体のアップロード / 画像変換 / ストーリー / リール |
| **fan-out on write** によるタイムライン (timeline_entries 事前展開) | hybrid push/pull (celebrity 対応) — 派生 ADR で扱う |
| プロフィール画面 (followers/following counter / 直近投稿) | 検索 / ハッシュタグ / 探索の本格実装 (mock のみ) |
| ai-worker の `/recommend` (mock) / `/tags` (mock) | LLM 呼び出し / 実画像認識 / レコメンドモデル学習 |
| DRF TokenAuthentication (1 経路) | OAuth / SSO / 2FA / email 検証 / password reset |
| **派生 ADR で扱う候補**: hybrid timeline (celebrity) / Redis ZSET cache / likes_count denormalize / 全文検索 / token rotation (Knox) | (上記いずれも本 ADR 0001-0004 のスコープ外として明示的に切り出し済み) |

---

## 主要な設計判断 (ADR ハイライト)

| # | 判断 | 何を選んで何を捨てたか |
| --- | --- | --- |
| [0001](docs/adr/0001-timeline-fanout-on-write.md) | **fan-out on write + Celery + Redis + `timeline_entries` 事前展開** | pull (read 時 IN scan) / hybrid (celebrity 対応) / 同期 fan-out / Redis ZSET cache を却下。celebrity 対応は派生 ADR |
| [0002](docs/adr/0002-follow-graph.md) | **Adjacency List + 双方向 index + denormalized counter (F 式更新)** | Adjacency Matrix / Closure Table / Neo4j / counter なし / Redis counter を却下 |
| [0003](docs/adr/0003-orm-n-plus-one.md) | **`select_related` / `prefetch_related` / `annotate` + `assertNumQueries` で件数固定** | debug-toolbar 観測のみ / GraphQL Dataloader / raw SQL / iterator() / 強い denormalize を却下 |
| [0004](docs/adr/0004-auth-drf-token.md) | **DRF TokenAuthentication + `Authorization: Token` ヘッダ (1 経路)** | SessionAuth (CSRF 煩雑) / JWT (perplexity と重複) / django-allauth (スコープ過剰) / 自前実装を却下 |

---

## ポート割り当て

| サービス | ポート | 備考 |
| --- | --- | --- |
| frontend (Next.js)  | 3045 | perplexity の 3035 から +10 |
| backend (Django)    | 3050 | perplexity の 3040 から +10 |
| ai-worker (FastAPI) | 8040 | perplexity の 8030 から +10 |
| MySQL               | 3311 | perplexity の 3310 から +1 |
| Redis               | 6380 | slack の 6379 から +1 |

---

## ローカル起動 / 動作確認ガイド

> Django/Celery/FastAPI/Next.js が **5 プロセス並走**する構成のため、最初は
> 「どこで何が動いているか」が分かりづらい。下の順番でセットアップすれば
> ターミナル 4-5 個でフル機能を試せる。

### 前提

- Docker / Docker Compose / Node.js 20+ / Python 3.12+
- macOS / Linux 想定 (Windows は WSL2 推奨)

---

### 0. 一括セットアップ (初回のみ)

リポジトリ root の `Makefile` にショートカットがある:

```bash
make instagram-setup
# 内訳:
#   docker compose up -d mysql redis        (3311 / 6380)
#   backend で venv + pip install + migrate
#   ai-worker で venv + pip install
#   frontend / playwright で npm install
```

セットアップが終わると以下のディレクトリ構造になっている:

```
instagram/
  backend/.venv/            # Django 用 venv
  ai-worker/.venv/          # FastAPI 用 venv (別物)
  frontend/node_modules/
  playwright/node_modules/
```

---

### 1. 4 つのターミナルで起動 (各タブを開きっぱなしにする)

| Tab | 起動するもの | コマンド | ポート |
| --- | --- | --- | --- |
| 1 | **Django backend** (DRF) | `make instagram-backend` | :3050 |
| 2 | **Celery worker** (fan-out) | `make instagram-celery` | (broker 経由) |
| 3 | **ai-worker** (FastAPI) | `make instagram-ai` | :8040 |
| 4 | **frontend** (Next.js) | `make instagram-frontend` | :3045 |

#### Celery worker を立てる理由

タイムラインの fan-out (ADR 0001) は本来 **非同期 Celery タスク**で実行される。
worker を立てない場合、`Post` 作成は成功するが **フォロワーの timeline に
反映されるのが永遠に遅延** する (broker にタスクが積まれたまま)。
- 自分の timeline には自分の post が同期 INSERT で即座に映る (signal)
- フォロワーの timeline / unfollow 後の削除は worker 必須

> **時短したい時 (UI 触るだけ)**: Tab 2 を立てる代わりに Tab 1 を
> `CELERY_TASK_ALWAYS_EAGER=True make instagram-backend` で起動すれば、
> Django プロセス内で fan-out を同期実行する。Playwright が使っているのと
> 同じ手法。

---

### 2. 疎通確認 (curl)

各サービスが立ったら順番に health を叩く:

```bash
curl -s http://localhost:3050/health           # → {"ok": true}      Django
curl -s http://localhost:8040/health           # → {"ok": true}      ai-worker
curl -sI http://localhost:3045 | head -1       # → HTTP/1.1 200 OK   Next.js
```

3 つとも 200 が返れば準備完了。

---

### 3. ブラウザで動作確認 (golden path)

http://localhost:3045 を開いて以下の流れを試す:

1. **register**: `/register` で `alice` / `password123!` を登録
   - 自動で `/` (timeline) にリダイレクト、空タイムラインが表示される
2. **post**: ナビの `post` をクリック → image_url + caption を入れて submit
   - timeline に自分の post が出る (self entry 同期 INSERT)
   - **「ai-worker でタグを提案」**ボタンで `/tags` の動作も確認できる
3. **2 人目を作る**: シークレットウィンドウ or 別ブラウザで `/register` から `bob` を登録
4. **bob が alice を follow**: bob 側で `/users/alice` を開いて follow ボタン
5. **alice の post が bob の timeline に出るか確認**:
   - bob 側で `/` を開く
   - 「alice の post が見える」= **fan-out が動いている**
   - もし見えなければ → Celery worker が走っていない (Tab 2 を確認)
6. **like / comment**: bob 側で alice の post の ♡ を押す → count + 1
   - 💬 リンクで `/post/[id]` 詳細ページに遷移、コメントを書く
7. **discover**: ナビの `discover` で **フォローしていないユーザの post** が出る (ai-worker `/recommend` 経由)
8. **logout**: 右上 logout で localStorage の token がクリアされる

---

### 4. Django ならではの確認手段

#### 4-1. Django Admin で生データを見る

```bash
cd instagram/backend && source .venv/bin/activate
python manage.py createsuperuser    # username / email / password を対話で入力
```

http://localhost:3050/admin/ にログインすると、`User` / `Post` / `Like` /
`Comment` / `Follow` / `TimelineEntry` を Web UI で CRUD できる。
**fan-out のデバッグに最も役立つ**:
- 「bob の post 作成 → TimelineEntry テーブルに alice 行ができたか」を直接確認
- counter denormalize の値を直接見られる
- 投稿を soft delete (deleted_at セット) する操作も可能

#### 4-2. Django shell (ORM REPL)

```bash
python manage.py shell
```

```python
>>> from accounts.models import User
>>> from posts.models import Post
>>> from timeline.models import TimelineEntry
>>> alice = User.objects.get(username='alice')
>>> alice.followers_count, alice.following_count, alice.posts_count
(0, 1, 3)
>>> Post.objects.filter(user=alice).count()
3
>>> TimelineEntry.objects.filter(user=alice).order_by('-created_at')[:5]
<QuerySet [<TimelineEntry: ...>, ...]>
```

#### 4-3. MySQL に直接繋ぐ

```bash
python manage.py dbshell
# または:
docker exec -it instagram-mysql-1 mysql -uinstagram -pinstagram instagram_development
```

```sql
SELECT id, username, followers_count, following_count, posts_count FROM users;
SELECT * FROM follow_edges;
SELECT user_id, post_id, created_at FROM timeline_entries ORDER BY created_at DESC LIMIT 10;
```

#### 4-4. counter drift の修復

signal が落ちて denormalized counter が真値とずれた場合:

```bash
python manage.py recount_user_stats --dry-run    # 差分だけ表示
python manage.py recount_user_stats              # 書き戻し
```

#### 4-5. テストを動かす

```bash
make instagram-backend-test    # pytest (Django + DRF) - 51 件
make instagram-ai-test         # pytest (FastAPI)      - 12 件
make instagram-frontend-lint   # lint + typecheck + build
make instagram-test            # 上記 3 つを一括
```

#### 4-6. Playwright で全自動 E2E

```bash
cd instagram/playwright && npx playwright install chromium    # 初回のみ
npm test
```

`webServer` で backend / ai-worker / frontend を自動起動 → register / post /
fan-out / like を chromium 実機で踏む。所要 ~12 秒。Celery を立てなくても
`CELERY_TASK_ALWAYS_EAGER=True` で eager 実行されるので Tab 2 不要。

---

### 5. トラブルシューティング

| 症状 | 原因 / 対処 |
| --- | --- |
| `python manage.py migrate` で `Access denied` | mysql コンテナの初期化前。`docker compose ps` で `healthy` を確認、init script (`infra/mysql-init/01-grant-test-db.sql`) が走り終わってから再実行。 |
| backend 起動時 `Can't connect to MySQL server on '127.0.0.1:3311'` | `make instagram-deps-up` を忘れている。`docker compose ps` で確認。 |
| Celery worker 起動時 `Connection refused (redis)` | Redis コンテナが立っていない。`make instagram-deps-up`。 |
| frontend が `CORS error` | `CORS_ALLOWED_ORIGINS` env を Django 側に設定 (default は localhost:3045 だけ)。 |
| frontend で操作後 `/login` に飛ばされる | token が 401 を食った。`apiFetch` が自動 logout した動作 (ADR 0004 仕様)。 |
| Post 作成しても follower の timeline に反映されない | Celery worker が動いていない。Tab 2 を確認するか EAGER mode で起動。 |
| follow しても followers_count が 0 のまま | signal が落ちた可能性。`python manage.py recount_user_stats --dry-run` で差分を見る。 |
| Playwright 実行時 `port 3050 already in use` | Tab 1 の Django dev server を止める (Playwright は自分で起動するため)。 |
| ai-worker `/recommend` が 401 | `X-Internal-Token` 不一致。Django 経由 (`/discover`) で叩けばトークンは自動付与される。直接叩きたいときは `-H 'X-Internal-Token: dev-internal-token'` を付与。 |

---

### 6. 終了

各タブで `Ctrl-C` で止めて、Docker は:

```bash
make instagram-deps-down       # mysql / redis 停止 (データは volume に残る)
docker compose -f instagram/docker-compose.yml down -v   # データごと消す
```

---

## ステータス

| コンポーネント | ステータス |
| --- | --- |
| ADR (0001-0004)             | 🟢 全 Accepted |
| architecture.md             | 🟢 ER / fan-out シーケンス / API 概観 / 起動順序まで記述 |
| Backend (Django/DRF)        | 🟢 Phase 4 完了 — `/discover` / `/tags/suggest` で ai-worker 経由口 + django-cors-headers (pytest 44 件 pass) |
| Celery worker               | 🟢 Phase 3 完了 — fan-out / backfill / unfollow remove / soft delete propagation の 4 task |
| ai-worker (FastAPI)         | 🟢 Phase 4 完了 — `/recommend` (Discovery feed mock) + `/tags` (deterministic mock) (pytest 8 件 pass) |
| Frontend (Next.js 16)       | 🟢 Phase 4 完了 — login/register/timeline/discover/post-new/profile + Tailwind v4 + useSyncExternalStore (typecheck + lint + build pass) |
| 認証 (DRF TokenAuthentication) | 🟢 Phase 2 完了 — register / login / logout / IsAuthenticated default |
| E2E (Playwright)            | 🟢 Phase 5 完了 — `instagram/playwright/` で register→post / fan-out / like の 3 spec が **実機 chromium で 3/3 pass (11.5s)** |
| インフラ設計図 (Terraform)  | 🟢 Phase 5 完了 — `infra/terraform/` (network/alb/ecs(4 service)/rds/elasticache/s3/cloudfront/iam/cloudwatch/secrets) `validate` pass |
| CI (GitHub Actions)         | 🟢 Phase 5 完了 — `.github/workflows/ci.yml` に instagram-{backend,frontend,ai-worker,terraform} 4 ジョブ追加 |

---

## 運用 / メンテナンス

### counter drift の修復

ADR 0002 / 0003 で denormalize した `users.followers_count / following_count / posts_count` が signal 例外で狂った場合は以下で修復する:

```bash
python manage.py recount_user_stats --dry-run    # 差分確認
python manage.py recount_user_stats              # 書き戻し
```

夜間 batch (cron / EventBridge Scheduler) からこのコマンドを叩く想定。

### ai-worker shared secret

ai-worker (`/recommend`, `/tags`) は `X-Internal-Token` を要求する (defense in depth)。Django は `settings.AI_WORKER_INTERNAL_TOKEN` から自動付与。本番では `INTERNAL_TOKEN` (ai-worker) と `AI_WORKER_INTERNAL_TOKEN` (Django) を Secrets Manager 経由の同じ強い値にする。`/health` だけは ALB / Service Discovery の health check 用に open。

---

## Future work (派生 ADR / 派生実装の余地)

「完成の定義」は満たしたが、以下は意図的に派生として切り出した:

- **hybrid timeline (celebrity 対応)** — 現状 fan-out on write のみ。フォロワー数 ≥ 10K で write amplification が破綻する。push と pull の混合は派生 ADR ([ADR 0001](docs/adr/0001-timeline-fanout-on-write.md))
- **timeline cache layer (Redis ZSET)** — ホットユーザの timeline を Redis に置く案。永続化二系統の整合性管理コストとセットで派生 ADR
- **block / mute / 非公開アカウント** — 現状は公開のみの follow。`follow_requests` テーブル + `accept` 経路は派生 ADR ([ADR 0002](docs/adr/0002-follow-graph.md))
- **likes_count / comments_count を `posts` に denormalize** — 現状 `annotate(Count(... distinct=True))`。スケール時は denormalize する派生 ADR
- **token rotation / Knox 移行** — DRF Token は無期限。TTL / rotation は派生 ADR ([ADR 0004](docs/adr/0004-auth-drf-token.md))
- **画像アップロード経路** — 現状 `image_url` 文字列のみ。S3 pre-signed PUT + 画像変換は別プロジェクト相当
- **検索 (FULLTEXT ngram)** — caption / username の全文検索。youtube プロジェクトと同じ仕組みで足せる
- **通知** — フォロー / いいね / コメントの通知 (Celery + email / WebSocket) は別スコープ

---

## ドキュメント

- [アーキテクチャ図](docs/architecture.md) — システム構成 / ER / fan-out シーケンス / API 概観 / index 一覧
- [ADR 一覧](docs/adr/)
  - [0001 タイムライン生成戦略 (fan-out on write)](docs/adr/0001-timeline-fanout-on-write.md)
  - [0002 フォローグラフの DB 設計](docs/adr/0002-follow-graph.md)
  - [0003 Django ORM N+1 と index 設計](docs/adr/0003-orm-n-plus-one.md)
  - [0004 認証方式 (DRF TokenAuthentication)](docs/adr/0004-auth-drf-token.md)
- リポジトリ全体方針: [../CLAUDE.md](../CLAUDE.md)
- API スタイル選定: [../docs/api-style.md](../docs/api-style.md)
- 共通ルール: [../docs/](../docs/) (coding-rules / operating-patterns / testing-strategy)

---

## Phase ロードマップ

| Phase | 範囲 | 状態 |
| --- | --- | --- |
| 1 | scaffolding + ADR 4 本 + architecture.md + docker-compose | 🟢 設計フェーズ完了 |
| 2 | Django scaffold (users / posts / follows / likes / comments) + DRF Token 認証 + 基本 CRUD + N+1 ガード | 🟢 完了 (pytest 23 件 / curl 経由で auth + CRUD smoke) |
| 3 | Celery + Redis 統合 + `timeline_entries` モデル + fan-out / backfill / unfollow / delete 4 task + `/timeline` endpoint + soft delete | 🟢 完了 (pytest 40 件 pass / `CELERY_TASK_ALWAYS_EAGER` で chain を結合検証) |
| 4 | ai-worker (FastAPI) `/recommend` `/tags` + frontend (Next.js timeline + プロフィール + 投稿フォーム) | 🟢 完了 (ai-worker pytest 8 件 / Django pytest 44 件 / Next.js build pass) |
| 5 | Playwright E2E + Terraform 設計図 + GitHub Actions CI workflows | 🟢 完了 (Playwright 3 spec / Terraform validate / ci.yml に 4 ジョブ) |
| 5+ | 後レビュー反映 (ai-worker shared secret / 401 redirect / tags pathological / comment UI / delete UI / counter drift 修復) | 🟢 完了 (Playwright **実機 3/3 pass** / pytest 51 + 12 / 派生 ADR 候補は Future work セクションに整理) |
