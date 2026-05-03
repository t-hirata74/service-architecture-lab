# Python コーディング規約

本リポの Python コードは 2 系統:

1. **ai-worker (FastAPI)** — `slack/ai-worker/` `youtube/ai-worker/` 等。AI / 数値計算 / モックの軽量サービス
2. **Django/DRF backend** — `instagram/backend/`。Web アプリ本体 (Rails 代替の言語別バックエンド)

下に **(A) ai-worker (FastAPI)** と **(B) Django (DRF) backend** を分けて書く。

---

## (A) ai-worker (FastAPI)

`slack/ai-worker/` で実際に採用している規約。役割は **AI 処理 / レコメンド / 検索ランキング / 非同期ワーカーのモック実装**。本物の LLM 呼び出しや外部 API は使わない (CLAUDE.md「外部 API 禁止」)。

### 技術スタック

- Python 3.13
- FastAPI + uvicorn
- pydantic v2 (リクエスト / レスポンスのモデル定義)
- `requirements.txt` で固定バージョン管理 (lock ファイル相当)

依存は最小に保つ。**numpy / pandas / sklearn 等は実際に必要になるまで入れない**。

---

## ディレクトリ構成

```text
ai-worker/
  main.py            # FastAPI app + endpoint
  requirements.txt
  README.md
```

機能が増えたら以下のように分割する:

```text
  app/
    __init__.py
    api.py           # FastAPI ルーティング
    schemas.py       # pydantic models
    services/        # 個別ロジック (要約 / 推薦 / etc.)
```

最初から分割しない。`main.py` が 200 行を超えたタイミングで切り出す。

---

## エンドポイント設計

- `GET /health` を必ず生やす（CI のスモークで叩く）
- 入力 / 出力は pydantic モデルで型付け
- パスは `/<verb>`（例: `/summarize`, `/recommend`）。RESTful ではなく **動詞ベース** にする（バッチ処理 / 単発計算が中心のため）

---

## pydantic モデル

- リクエスト / レスポンスは別クラスにする（`SummarizeRequest` / `SummarizeResponse`）
- バリデーションは `Field` の `min_length` / `max_length` / `default_factory` を使う
- 「あり得ない」入力に対する手書きの assert は書かない。pydantic が落とす

---

## モック実装の方針

- 決定論的（同じ入力で同じ出力）にする。テストで再現できるように
- ランダム / 時刻依存 / I/O は避ける
- 結果には `(mock)` を入れるなど、本物でないことが明示的に分かる文字列を返す

---

## Rails からの呼び出し

- Rails 側 `AiWorkerClient` (`slack/backend/app/services/ai_worker_client.rb`) から HTTP で呼ばれる
- ベース URL は環境変数 `AI_WORKER_URL`（slack: デフォルト `http://localhost:8000` / youtube: デフォルト `http://localhost:8010`）
- Rails 側で open 2s / read 10s タイムアウトを設定済み。Python 側も**重い処理を作らない**

### graceful degradation を前提に書く

ai-worker は **本流ではない** 補助レイヤー。Rails 側は失敗時に `200 + degraded: true`
で返す（[`operating-patterns.md`](../operating-patterns.md#graceful-degradation)）。
そのため Python 側で:

- 例外を返すよりも **空配列 / 既定値で 200 を返す** ほうが望ましい
- どうしても異常系を返す場合は **5xx ではなく 4xx**（例: バリデーションエラーは 422）
- ヘルスチェック `/health` は **依存先（DB / モデルロード）に左右されず** 200 を返す
- ジョブ完了通知 / コールバックを Rails に投げる方向の通信はしない（pull のみ）

### バイナリレスポンス

サムネ画像のような binary は `Response(content=bytes, media_type="image/png")` で返す。
JSON を期待する Rails 側のクライアントが切り替えられるよう、エンドポイントを分ける。

---

## Lint / Format

- 当面 `ruff` などは導入していない。FastAPI / pydantic の型でコンパイル相当の検査は得られている前提
- 規模が大きくなったら `ruff` + `ruff format` を入れる方針（その時点で ADR を立てる）

---

## テスト

- 現時点ではテストコードを書いていない（モック実装のため）
- ロジックが増え始めたタイミングで `pytest` を導入する。導入時は CI に組み込む

---

## CI で検証していること（最小）

`.github/workflows/ci.yml` の `slack-ai-worker` ジョブ:

1. `pip install -r requirements.txt` で依存解決
2. `python -c "import main"` で import が通ることを確認
3. `uvicorn main:app` を起動 → `/health` を叩いて 200 を確認

ロジックが増えたら `pytest` ジョブを追加する。

---

## ai-worker でやらないこと

- 本物の LLM / 外部 API 呼び出し
- 大きな ML 依存の導入 (先回り禁止)
- 非同期化 (async / await) を学習目的なしで入れる

---

## (B) Django (DRF) backend

`instagram/backend/` で実際に採用した規約。Rails 主軸のオーナーが Python/Django で実装したらどう書くか、を整理した一次資料。

### 技術スタック

- Python 3.13 / Django 5.2 / djangorestframework 3.15
- MySQL (PyMySQL ドライバで mysqlclient の C ビルド依存を回避) + Redis
- Celery 5 (broker = Redis)
- pytest + pytest-django + `python-decouple` (env 駆動 settings)

### ディレクトリ構成 (apps を**ドメイン縦割り**にする)

```text
backend/
  config/
    __init__.py     # PyMySQL の install_as_MySQLdb() を含む
    settings.py     # decouple 経由で env を読む
    urls.py
    celery.py
    wsgi.py / asgi.py
  accounts/
    models.py serializers.py views.py urls.py admin.py signals.py
    migrations/
    management/commands/recount_user_stats.py     # 運用コマンド
    tests/
  follows/    # 同様
  posts/      # queries.py を追加 (N+1-safe queryset 集約)
  timeline/   # tasks.py を追加 (Celery)
```

「ある機能の責務をすべて 1 ディレクトリに集約する」のが Django app の利点。Rails モノリスの横断レイヤ (`app/models/` `app/controllers/` 等) と異なる思想。

### ORM の N+1 制御 — `select_related` / `prefetch_related` を**明示**

Rails の `includes` が自動推論するのに対し、Django は **JOIN するか別 query にするかをコードで宣言する**:

```python
# posts/queries.py
def posts_for_viewer(viewer):
    return (
        Post.objects.filter(deleted_at__isnull=True)
        .select_related("user")              # FK は JOIN
        .annotate(
            likes_count=Count("likes", distinct=True),     # ※ distinct 必須
            comments_count=Count("comments", distinct=True),
        )
        .prefetch_related(
            Prefetch(
                "likes",
                queryset=Like.objects.filter(user=viewer),
                to_attr="liked_by_me_list",                # viewer 文脈の prefetch
            )
        )
    )
```

**規律**:

- **list view ごとに専用 queryset 関数**を `<app>/queries.py` に置く。view では `qs = posts_for_viewer(request.user)` を 1 行呼ぶだけ
- `annotate(Count(...))` を**複数の reverse relation に同時適用**するときは `distinct=True` を**必ず付ける** (Django 標準の罠: JOIN が直積になり count が膨れる)
- `Prefetch(..., to_attr=...)` で「viewer に依存する prefetch」を明示。serializer 側では `getattr(obj, "liked_by_me_list", None)` で silent fallback せず、**`hasattr` で必須化して prefetch 忘れを `AssertionError` で表に出す**:

```python
def get_liked_by_me(self, obj):
    if not hasattr(obj, "liked_by_me_list"):
        raise AssertionError("posts_for_viewer() を経由していない")
    return bool(obj.liked_by_me_list)
```

### `F()` expression で原子更新

Rails AR の `increment_counter` 相当。`User.objects.get(...); user.count += 1; user.save()` は race するので **必ず `F()`**:

```python
User.objects.filter(pk=...).update(
    followers_count=F("followers_count") + 1,
)
```

`Q()` と組み合わせれば複雑な条件 update も race なく書ける。

### Signal + `transaction.on_commit` で副作用を分離

Rails の `after_commit` 相当。`save()` 直後の Celery enqueue は `transaction.on_commit` 経由で **commit 後に走らせる**:

```python
@receiver(post_save, sender=Post)
def on_post_created(sender, instance, created, **kwargs):
    if not created:
        return
    pk = instance.pk
    transaction.on_commit(lambda: fanout_post_to_followers.delay(pk))
```

**理由**: `ATOMIC_REQUESTS=True` のとき、commit 前にタスクが走ると Post を SELECT できない。`on_commit` で書けば auto-commit / atomic どちらでも等価。詳細: [operating-patterns.md §10](../operating-patterns.md#10-fan-out-on-write--非同期ワーカー--同期-self-entry--soft-delete-instagram)。

### `bulk_create(ignore_conflicts=True)` で at-least-once を吸収

Celery task の重複実行に備えて UNIQUE 制約 + `ignore_conflicts=True` の組合せを基本に:

```python
TimelineEntry.objects.bulk_create(entries, ignore_conflicts=True)
```

### Settings は `python-decouple` で env 駆動 1 ファイル

```python
# config/settings.py
from decouple import config

DEBUG = config("DJANGO_DEBUG", default=True, cast=bool)
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.mysql",
        "NAME": config("MYSQL_DATABASE", default="instagram_development"),
        ...
    }
}
CELERY_TASK_ALWAYS_EAGER = config("CELERY_TASK_ALWAYS_EAGER", default=False, cast=bool)
```

Rails の `database.yml` + `secrets.yml` + `application.yml` 分割と異なり、**1 ファイル + env**が Django の流儀。

### Celery + Django settings の罠

`app.config_from_object("django.conf:settings", namespace="CELERY")` を使うと、**`celery_app.conf.task_always_eager = True` を直接書いても効かない** (settings 側を毎回読みに行く)。テストでも production override でも **必ず Django settings 側を書き換える**:

```python
from django.conf import settings
settings.CELERY_TASK_ALWAYS_EAGER = True   # これが効く
```

詳細: [testing-strategy.md](../testing-strategy.md) の pytest-django セクション。

### Management commands で運用コマンドを置く

Rails の `rake task` 相当。`<app>/management/commands/<command_name>.py` に `class Command(BaseCommand)` を書く:

```python
class Command(BaseCommand):
    help = "..."
    def add_arguments(self, parser):
        parser.add_argument("--dry-run", action="store_true")
    def handle(self, *args, dry_run=False, **opts):
        ...
        self.stdout.write(self.style.SUCCESS(f"fixed N user(s)"))
```

`argparse` 統合 + `stdout / style` helper が標準で付く。実例: `instagram/backend/accounts/management/commands/recount_user_stats.py`。

### Django Admin を**最初から**書く

`<app>/admin.py` に `@admin.register(Model)` で 1 行登録するだけで、ログイン / 一覧 / 検索 / フィルタ / CRUD UI が全部出る。**fan-out のデバッグや counter drift 確認に最も役立つ**:

```python
@admin.register(TimelineEntry)
class TimelineEntryAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "post", "created_at")
    raw_id_fields = ("user", "post")    # FK が大量にある時は必須
```

`raw_id_fields` を付けないと FK select box が全件 dropdown になり、ユーザ数が多いと Admin が固まる。

### DRF ViewSet ではなく **`@api_view` 関数ビュー**で書く (instagram の選択)

ViewSet の `def list / def create` は magic で動詞ごとの分岐が見えづらい。instagram プロジェクトでは小規模性を優先して関数ビュー + 動詞分岐を採用:

```python
@api_view(["POST", "DELETE"])
def follow(request, username):
    if request.method == "POST":
        ...
    else:
        ...
```

ロジックが大きくなったら ViewSet に切り替える ADR を立てる。

### Django backend でやらないこと

- **モデル callback (`save()` override) で副作用**: signal + on_commit に統一
- **`ATOMIC_REQUESTS=True` を黙って入れる**: ADR で意図を残してから (default は False のまま)
- **`F()` を使わずに `obj.count += 1; save()`**: race する
- **`select_related` / `prefetch_related` を書き忘れたまま list view を追加**: N+1 不変条件試験 ([testing-strategy.md](../testing-strategy.md) を 1 本書くまで PR をマージしない
