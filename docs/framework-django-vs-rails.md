# Django (DRF) と Rails の比較メモ

本リポは Rails 主軸のオーナーが Python / Go の知識を並走で獲得することを
方針とする ([CLAUDE.md「言語別バックエンド方針」](../CLAUDE.md#学習方針言語別プロジェクトと-rails-リプレイス))。
`instagram` プロジェクトを Django/DRF + Celery で実装した結果、
**「Rails と比べて何が違ったか」**「**いつ Django を選ぶか**」を半年後の
自分が読み返せるよう整理した一次資料。

---

## instagram で実際に効いた「Django ならでは」5 つ

### 1. Django Admin — 1 行登録で全モデル CRUD UI

```python
# instagram/backend/timeline/admin.py
@admin.register(TimelineEntry)
class TimelineEntryAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "post", "created_at")
    raw_id_fields = ("user", "post")
```

これだけで http://localhost:3050/admin/ で **ログイン / 一覧 / 検索 /
フィルタ / CRUD UI** が出る。Rails で同等を得るには `rails_admin` /
`activeadmin` gem を入れて DSL を書く。今回 fan-out のデバッグで
`TimelineEntry` Admin 一覧を直接眺めて「bob の post → alice 行が増えたか」
を可視化できたのは Django Admin だけが提供する開発体験。

### 2. `select_related` vs `prefetch_related` の **明示的な区別**

```python
# instagram/backend/posts/queries.py
Post.objects.filter(deleted_at__isnull=True)
    .select_related("user")              # FK は JOIN
    .prefetch_related(
        Prefetch("likes",
                 queryset=Like.objects.filter(user=viewer),
                 to_attr="liked_by_me_list"),  # 別 query (IN)
    )
    .annotate(likes_count=Count("likes", distinct=True))
```

Rails の `User.includes(:posts, :likes)` は **AR が JOIN するか別 query
にするかを推測**して決める (`preload` / `eager_load` で強制可能だが煩雑)。
Django は **「この関係は 1 query で取る (JOIN)」「この関係はバルクで取る
(IN)」を毎回コードで宣言する**ので、N+1 制御が「コードに書いてある」状態。
`Prefetch(..., to_attr=...)` で「この prefetch は要求側の文脈に依存する」
を明示するのも強い (今回 `liked_by_me_list` が `viewer` ごとに異なる)。

### 3. `F()` expression での原子更新

```python
# instagram/backend/follows/signals.py
User.objects.filter(pk=...).update(
    followers_count=F("followers_count") + 1
)
```

`UPDATE users SET followers_count = followers_count + 1` を生成。
Rails AR にも `User.increment_counter(:followers_count, id)` があるが、
`F()` は **集計式 / ソート / where 句**にも使える汎用品で、`Q()` と
組み合わせれば複雑な条件 update も race なく書ける。counter denormalize
の race 対策で効いた。

### 4. `assertNumQueries` を **CI で固定する文化**

```python
# instagram/backend/posts/tests/test_query_count.py
with CaptureQueriesContext(connection) as ctx_5:
    res = authed_client.get("/posts")  # N=5
count_5 = len(ctx_5.captured_queries)

# ... 15 件追加 ...

with CaptureQueriesContext(connection) as ctx_20:
    res = authed_client.get("/posts")  # N=20
count_20 = len(ctx_20.captured_queries)

assert count_5 == count_20, "post list must not N+1"
```

「件数固定」ではなく **「N に依存しない」不変条件**で書く。Rails でも
`bullet` gem で N+1 検出はできるが、**「list endpoint を増やしたら必ず
query count test を 1 本書く」が ADR 0003 で文化として明文化できた**のは
Django + DRF + pytest-django の組み合わせが構造的にそれを促すから。

### 5. **Apps によるドメイン縦割り**

```text
instagram/backend/
  accounts/   models.py signals.py views.py urls.py admin.py tests/
  follows/    models.py signals.py views.py urls.py admin.py tests/
  posts/      models.py signals.py views.py urls.py admin.py queries.py tests/
  timeline/   models.py signals.py tasks.py views.py urls.py admin.py tests/
  config/     settings.py urls.py celery.py
```

各 app に必要なものが揃う。**ファイル名で責務が探せる**。Rails モノリスは
`app/models / app/controllers / app/jobs` という横断レイヤ分割なので、
ある機能を理解するために `Post` model + `PostsController` + `PostMailer` +
`PostJob` を 4 ディレクトリ跨ぎで読む必要がある。Django apps はドメイン
縦割りなのでルーティング理解が早い。

> Rails Engine でも同じことができるが、設定コストが Django app より重い。

---

## Rails vs Django (この project 越しの比較)

### Django が優位な点

| 項目 | Django | Rails |
| --- | --- | --- |
| 管理 UI | **Admin が標準** | gem 必要 (`rails_admin` / `activeadmin`) |
| migrations | model 差分から `makemigrations` で**自動生成** | 1 つずつ手書き |
| 型ヒント | Python 3.13 + Django 5.x で **first-class** | sorbet / RBS は後付け |
| ORM の prefetch 制御 | `select_related` / `prefetch_related` で**明示** | `includes` が推論 (ハマる時はハマる) |
| async I/O | Django 4.0+ で `async def view` 対応 | Hotwire/Turbo は別軸、async は薄い |
| Settings | 1 ファイル + `python-decouple` で env | `database.yml` / `secrets.yml` / `application.yml` 複数 |
| Python エコシステム | numpy / pandas / sklearn / FastAPI が**同じ言語** | 別言語サービス必須 (例: 本リポの ai-worker) |
| **DRF (REST framework)** | permissions / throttle / pagination / viewset が**標準で整備** | `rails-api` は薄い、ほぼ自前 |

特に **Python 数値計算と地続き**は本リポの設計思想 (Rails ↔ Python ai-worker
の分離) を Django なら**同言語で完結**できる、という選択肢を生む。
学習目的でわざわざ分離したが、現実のプロジェクトでは Django 1 プロセスに
ML 推論を同居させる選択も合理的。

### Rails が優位な点

| 項目 | Rails | Django |
| --- | --- | --- |
| Conventions over Configuration | scaffolding 1 発で controller + view + route | urls + views + serializers + forms を分けて書く |
| AR の単純さ | `User.find(1)` | `User.objects.get(pk=1)` (ちょっと冗長) |
| relation traversal | `user.posts.create(...)` | `Post.objects.create(user=user, ...)` |
| Hotwire / Turbo | SPA レスでフロント書ける | 公式の同等品なし、Next.js 別プロセス |
| バックグラウンド job | **Solid Queue で Redis 不要** (Rails 8) | Celery + Redis / RabbitMQ broker 必須 |
| 認証 gem | `Devise` / `rodauth` で 1 経路 + OAuth + 2FA まで | `django-allauth` あるが設定が多い |
| Console の auto-reload | `rails console` で変更が反映 | `python manage.py shell` は再起動 |
| i18n | 早熟 | できるが Rails ほど洗練されてない |

特に **Rails 8 + Solid Queue は「Redis なし」を選択肢にできる** (本リポの
youtube プロジェクトで証明済み)。Django + Celery は broker (Redis or
RabbitMQ) 必須で依存サービスが 1 つ増える。

---

## どういう時に Django を選ぶか

### Django を選ぶ判断軸

- **管理画面が初日から欲しい** → Admin がそのまま出る
- **Python の ML / 数値計算スタックと地続きにしたい** → numpy / pandas / sklearn が同言語
- **DRF で API 中心の SaaS を作る** → permissions / throttling / pagination が成熟
- **巨大スケールでの実績を踏襲したい** → Instagram / Pinterest / Disqus などが採用
- **チームが Python に強い** → ML/データ職と Web 開発の境界がない

### Rails を選ぶ判断軸

- **Hotwire / Turbo で SPA レスにしたい**
- **Redis を立てずに非同期 job をやりたい** (Rails 8 Solid Queue)
- **scaffolding でとにかく速く作りたい**
- **チームが Ruby + 全部入りの規約を好む**

---

## このプロジェクトで一番「Django で良かった」と思った 1 点

**`assertNumQueries` で N+1 を CI 固定する文化** が一番効いた。
Rails でも書けるが、**「list endpoint を増やしたら必ず query count test を
1 本書く」が ADR 0003 として明文化できた**のは Django + DRF + pytest-django
の組み合わせが構造的にそれを促すから。

これは **「Django が偉い」という話より、「Django/DRF が REST API 中心の
設計を強制してくる結果、N+1 を可視化する圧力が常にかかる」** という
間接的なメリット。Rails で同じ文化を作るには意識的な努力が要る。

---

## 関連

- [coding-rules/python.md](coding-rules/python.md) — Django (DRF) のコーディング規約 + ai-worker (FastAPI) の規約
- [operating-patterns.md](operating-patterns.md) §10 fan-out on write (Celery 経路) / §11 denormalized counter
- [testing-strategy.md](testing-strategy.md) — pytest-django + N+1 不変条件 + Celery EAGER + on_commit 同期化
- 実例: `instagram/backend/`、`instagram/docs/adr/0001-0004`
