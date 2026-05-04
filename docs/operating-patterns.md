# 運用パターン (横断メタガイド)

slack と youtube を実装する中で **両プロジェクトに独立に発生した共通パターン** を、
リポジトリ全体の運用知として残す。CLAUDE.md より具体的な「実装で守る規律」のレイヤー。

---

## 1. Phase 駆動 MVP

新しいプロジェクトは **5 段階の Phase** で進める。両プロジェクトでこの分割が機能した。

| Phase | 範囲 | 達成判断 |
| --- | --- | --- |
| 1 | プロジェクト雛形 + 各サービス疎通 | docker compose up + `curl /health` 通過 |
| 2 | リソース CRUD + 一覧/詳細 UI | フロントから seed データが見える |
| 3 | サービス固有の **non-trivial 処理**<br/>(状態機械 / WebSocket / 権限グラフ 等) | RSpec で不変条件を縛る |
| 4 | ai-worker / 他境界の統合 | graceful degradation を含めて動作確認 |
| 5 | 検索 + E2E + Terraform + CI | 完成の定義（CLAUDE.md）満たす |

### Phase 駆動が効く理由

- **Phase 3 が技術課題の山場**: ここまでの土台があるから state machine や WebSocket の議論に集中できる
- **Phase 5 が "完成の定義" の網羅**: 検索 / E2E / Terraform / CI の4つは「やる/やらない」を毎回考えるのではなく **必ず通す関門** にすることでブレない
- **各 Phase 終了時に commit + README 更新**: 進捗が外から見える

### Phase をスキップするケース

- **Phase 2 と 3 の前後逆転**: state machine が中心テーマで CRUD が薄い場合 (例: stripe の idempotency)
- **Phase 4 不要**: ai-worker 境界が学習対象にならないドメイン (例: figma の CRDT は frontend 側)

---

## 2. Graceful degradation

外部依存（ai-worker / 検索エンジン / 通知配信）が落ちても **本流の操作は止めない**。

### 規約

| レイヤー | 失敗時の振る舞い |
| --- | --- |
| Service オブジェクト | 既知のエラーは独自例外（`Client::Error` / `Client::Timeout`）、それ以外は raise |
| Job (Active Job) | 例外を握って **`Rails.logger.warn` のみ**。リトライしない |
| Controller (REST) | **`200 + degraded: true`** で空配列 / 空サマリを返す。`502/503` はクライアントを混乱させるので避ける |
| Frontend | `degraded` フラグを見てバナー表示。基本機能（一覧 / 詳細）は維持 |

### 例

- youtube: ai-worker 不通 → `/videos/:id/recommendations` が `{ items: [], degraded: true }` で 200
- slack: ai-worker 不通 → `/channels/:id/summary` が要約欄を空で返す。チャット送受信は無関係に動く

### 例外: 業務クリティカルな依存

決済 (stripe), 認証 (rodauth) のような **本流の不可分な依存**は graceful degradation しない。
明示的に `503 Service Unavailable` で短時間リトライ可能であることを伝える。

### 例外: SSE long-lived stream の三段階 degradation (perplexity)

SSE のような **応答途中で「失敗の意味」が変わる**経路は単純な「200 + degraded」に収まらない。
perplexity の RAG パイプライン (ADR 0003) では領域を 3 つに分けて規律を変える:

| 領域 | タイミング | 失敗時 |
| --- | --- | --- |
| §A | SSE 開始前 (retrieve / extract 中) | **HTTP 5xx** で素直に返す。frontend は SSE を開かない |
| §B | SSE 開始後 / done 前 (synthesize 中) | **`event: error`** を流して close。HTTP status は 200 のまま (既に開いているため変えられない) |
| §C | done 受信後 (Rails 側永続化中) | `Answer.transaction` で **answer + citations を原子的に**永続化。失敗したら `event: error` |

> ポイントは「`event: error` を `degraded: true` の代わりに使う」「§A だけは 5xx を許可する」の 2 点。
> 同じ `2. Graceful degradation` の規律を SSE 用に拡張した形 (詳細: perplexity ADR 0003)。

---

## 3. ローカル実装 + Terraform 二段構え

CLAUDE.md は「Terraform は実行しないが設計図として用途」と定めるが、運用上の規律として:

### コードは **本番想定との乖離を ADR に記録**

例: youtube ADR 0001 (Solid Queue 採用) は本番では SQS を使う想定。乖離は ADR の「引き受けるトレードオフ」セクションで明示し、Terraform 側に対応する `sqs.tf` を残す。

### Terraform は **`terraform validate` を CI で必須**

apply はしないが validate は通す。lint と同じ位置付けで品質ゲートにする。

```yaml
- name: terraform fmt -check -recursive
- name: terraform init -backend=false -input=false
- name: terraform validate
```

### 設計図と実装の対応を README で明示

```text
youtube/infra/terraform/sqs.tf
  → 本番想定で Solid Queue を SQS に差し替えるポイント (ADR 0001 と整合)
```

---

## 4. ADR 運用

CLAUDE.md と `docs/adr-template.md` に詳細があるが、運用上の追加ルール:

### Phase の進行と ADR ステータス

- Phase 1 終了時: 主要 ADR を **Proposed** で書く（実装前に判断軸を残す）
- 各 Phase 終了時: 該当 ADR を **Accepted** に昇格 + 実装ポインタを更新
- 別 ADR で覆す場合: **Superseded by ADR NNNN** に変更（削除しない）

### 「これを守るテスト」を ADR に必ず書く

ADR の最後の `## このADRを守るテスト / 実装ポインタ` セクションは省略しない。
半年後に ADR を読み直したとき、**コードのどこを見れば判断が活きているか** がわかる。

### 共通方針 ADR は `docs/` に、プロジェクト固有 ADR は `<service>/docs/adr/` に

例:
- `docs/api-style.md` — リポ全体の REST/GraphQL 方針
- `youtube/docs/adr/0006-production-aws-architecture.md` — youtube 固有の本番構成

---

## 5. コミット粒度

slack / youtube とも、**コンポーネント単位 × 概念的なまとまり** で 5〜8 コミットに分割する。

| 種類 | type プレフィクス | 例 |
| --- | --- | --- |
| 設定追加 | `chore(<service>)` | `.gitignore`、`docker-compose.yml` |
| 機能追加 | `feat(<service>/<layer>)` | `feat(youtube/backend): 状態機械を実装` |
| テスト | `test(<service>)` | `test(youtube/playwright): browse / search / upload` |
| インフラ | `feat(<service>/infra)` | `feat(youtube/infra): 本番想定 Terraform` |
| CI | `ci` | `ci: youtube ジョブを追加` |
| ドキュメント | `docs(<service>?)` | `docs(youtube): ADR 0006 追加` |
| リファクタ | `refactor(<service>)` | `refactor(youtube): API バージョニング撤去` |

### 1 コミット = 1 概念

- **コードと README は別コミット**（README は最後にまとめて同期）
- **コードと ADR は同じコミット**（実装と意図を一緒に commit）
- **依存追加と使用箇所は同じコミット**（Gemfile + 使用コード）

---

## 6. 外部依存の追加判断

新しい gem / npm package を入れるときは以下を満たす:

1. **学習対象に直接寄与する**（slack の `rodauth-rails` は認証パターン、youtube の `solid_queue` は Rails 8 標準キュー）
2. **代替が標準ライブラリで書けないか** 検討（HTTP は `Net::HTTP` で十分、`faraday` は不要）
3. **ADR で言及**（重要な依存は判断軸を残す）

導入していい例:
- ✅ Rails 標準を補う公式系（`solid_queue`, `solid_cache`, `bootsnap`, `kamal`）
- ✅ テスト品質を底上げする（`rspec-rails`, `factory_bot_rails`, `webmock`）
- ✅ 学習対象そのもの（GraphQL なら `graphql-ruby`）

導入を渋る例:
- ❌ シリアライザ gem (`active_model_serializers` 等) — controller プライベートメソッドで十分
- ❌ HTTP クライアント gem (`faraday`, `httparty`) — `Net::HTTP` で十分
- ❌ pundit / cancancan — 権限ロジックがアプリの主役の場合だけ（github 候補）

---

## 7. 内部 trusted ingress (REST + 共有トークン)

外向きは GraphQL / REST、**ai-worker → backend のように内部 worker から状態を書き込む経路は内向き REST + 共有トークン認証**で分ける。

```ruby
# github/backend/app/controllers/internal/commit_checks_controller.rb
class Internal::CommitChecksController < ApplicationController
  before_action :authenticate_internal!

  private

  DEV_DEFAULT_TOKEN = "dev-internal-token".freeze

  def authenticate_internal!
    expected = ENV["INTERNAL_INGRESS_TOKEN"].presence || DEV_DEFAULT_TOKEN
    # 本番でデフォルトトークンが残っていたら即拒否 (誤デプロイ防御)
    if Rails.env.production? && expected == DEV_DEFAULT_TOKEN
      head :service_unavailable
      return
    end
    provided = request.headers["X-Internal-Token"]
    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(expected.to_s, provided.to_s)
  end
end
```

**意図**:
- 外向き API (GraphQL / REST + OpenAPI) は **field 単位認可 + 公開スキーマ**で重い
- 内向きの「処理結果を返すだけ」の経路まで GraphQL に乗せると、認可レイヤーが二重になり遅い
- 共有トークンで十分（呼び出し側は VPC 内など信頼できるネットワーク前提）。ローカルは `dev-internal-token` というリテラルで OK だが **本番では env で必須化** + 本番デフォルト値検出ガード

**`secure_compare` を使う**: `==` だと timing attack が可能になる。`ActiveSupport::SecurityUtils.secure_compare`。

実例: `github/backend/app/controllers/internal/commit_checks_controller.rb`、ai-worker 側 `github/ai-worker/main.py` の `httpx.post(...)`。

---

## 8. 信頼境界 — 外部出力を永続化レイヤで再検証する (perplexity)

ai-worker / LLM / 外部サービスの出力を **そのまま信用して永続化しない**。
永続化と認可と同じ層 (= Rails) で **同じデータをもう一度検証する**。

perplexity の CitationValidator (ADR 0004) が典型例:

- ai-worker (mock LLM) は本文中に `[#src_<n>]` 形式の引用 marker を埋めて返す
- 同時に「このマーカーは valid」というメタ情報も返す
- **Rails はメタ情報を捨てて**、自分が ai-worker に渡した `allowed_source_ids` と
  正規表現で抽出した marker を **再照合**して valid 判定する
- 違反 marker は `event: citation_invalid` で frontend に通知するが、**永続化は valid
  通過分のみ** (ADR 0003 §C と組み合わせて `Answer.transaction` で原子的に書く)

**意図**:
- ai-worker は信頼境界の外。「メタ情報を信じて INSERT」をすると、ai-worker のバグや
  プロンプト経由の prompt injection で **不整合な citations が DB に残る**
- 認可 (current_user の query か?) と同じレイヤで「整合性」(allowed_source_ids 内か?)
  を検証することで **チェック漏れの face を 1 枚に絞る**
- chunk 境界をまたぐ marker (`[#sr` で chunk 終わり / 次が `c_3]`) は tail buffer で
  吸収する partial parser を書く必要が出るが、**それでも信頼境界は Rails 側に置く価値**がある

応用しうる先:
- LLM 出力の構造化 (JSON schema 検証 / function calling 結果の引数チェック)
- 外部 OAuth provider から渡る user 属性 (id / email を whitelist で再 lookup)
- ai-worker からの SQL-like パラメータ (chunk_id を allowed list で必ず正規化)

実例: `perplexity/backend/app/services/citation_validator.rb` + `sse_proxy.rb`。

---

## 9. テスト時のキャッシュ取り回し (urql + Playwright)

`urql` の `cache-and-network` ポリシーは「キャッシュを返しつつ裏で fetch する」。Playwright で API を直接叩いて状態を変えた後に画面を再描画したい場合は **`page.reload()` で確実に取り直す**:

```ts
// ai-worker → backend に check を upsert させた直後の画面状態を見る
await ai.post("/check/run", { ... });
await page.reload();
await expect(page.getByText("FAILURE").first()).toBeVisible();
```

`page.goto()` の再呼び出しでは urql の memory cache が残るので、状態変更を反映できないことがある。reload なら HTML から取り直して urql client もリセットされる。

実例: `github/playwright/tests/check_aggregation.spec.ts`。

---

## 10. fan-out on write — 非同期ワーカー + 同期 self entry + soft delete (instagram)

タイムライン / 通知 / 検索 index 等、**read が write より圧倒的に多い**領域では「投稿時に follower / 購読者全員の事前展開先に書き込んでおく」パターンが効く。slack の WebSocket fan-out (リアルタイム) / youtube の Solid Queue (state machine) と並ぶ非同期ワーカーの 3 番目の典型例。instagram プロジェクト ([ADR 0001](../instagram/docs/adr/0001-timeline-fanout-on-write.md)) で確立した規律:

### 規律 1: 投稿者本人の self entry は **同期 INSERT**

```python
# instagram/backend/timeline/signals.py
@receiver(post_save, sender=Post)
def on_post_created(sender, instance, created, **kwargs):
    if not created:
        return
    # self entry: 投稿者は即座に自分の post を timeline で見られる UX
    TimelineEntry.objects.get_or_create(
        user_id=instance.user_id, post_id=instance.pk,
        defaults={"created_at": instance.created_at},
    )
    pk = instance.pk
    transaction.on_commit(lambda: fanout_post_to_followers.delay(pk))
```

「自分の post が自分の timeline に映るまで Celery 待ち」では UX が壊れる。**self だけ同期 INSERT、他 follower は async fan-out** という非対称が答え。

### 規律 2: `transaction.on_commit` で enqueue 経路を統一

`save()` 直後に `.delay()` すると、`ATOMIC_REQUESTS=True` のときに **transaction commit 前にタスクが走り Post を SELECT できない**事故が起きる。`transaction.on_commit(lambda: ...)` で「commit 後に enqueue」を強制すれば、auto-commit でも atomic でも等価に動く。Rails の `enqueue_after_transaction_commit` ([coding-rules/rails.md](coding-rules/rails.md)) と等価のパターン。

### 規律 3: at-least-once + UNIQUE で冪等化

```python
@shared_task
def fanout_post_to_followers(post_id):
    follower_ids = Follow.objects.filter(followee_id=post.user_id) \
                                  .values_list("follower_id", flat=True)
    entries = [TimelineEntry(user_id=fid, post_id=post.pk, ...)
               for fid in follower_ids if fid != post.user_id]
    TimelineEntry.objects.bulk_create(entries, ignore_conflicts=True)
```

- `UNIQUE (user_id, post_id)` を `timeline_entries` に張る
- `bulk_create(ignore_conflicts=True)` で再実行を吸収
- self を `if fid != post.user_id` で除外 (UNIQUE で吸収はされるが無駄を避ける)

### 規律 4: **soft delete + 非同期削除 fan-out**

hard delete + DB CASCADE は **非同期 fan-out 先と競合**する。Post 作成直後に Celery が走っている状態でユーザが即削除すると、fan-out 先テーブルが先に消えて INSERT が `IntegrityError` で死ぬケース。
解決: Post を soft delete (`deleted_at` セット) + `on_commit` で非同期削除タスクを enqueue する経路に統一する。read 側は `posts.deleted_at IS NULL` で必ず除外。

実例: `instagram/backend/posts/models.py:Post.soft_delete()`、`instagram/backend/timeline/tasks.py:remove_post_from_timelines`。

### 規律 5: 新規 follow / unfollow も同じ経路で **backfill / unwind**

- follow 作成 → followee の直近 N 件を follower の timeline に backfill
- unfollow → follower の timeline から followee の post を一括削除

これも `Follow` の `post_save` / `post_delete` signal で `on_commit` → Celery task で処理する。**fan-out / backfill / unwind / delete propagation の 4 task に責務を分けて命名**すると、各 task が「この event のためだけのハンドラ」になり、テストも書きやすい。

---

## 11. denormalized counter + 自動修復 management command (instagram)

`User.followers_count / following_count / posts_count` のような **「常時表示で `SELECT COUNT(*)` するには高すぎる」counter** は denormalize して `users` テーブルに持つのが定石。読み取りは速いが、signal が落ちて真値とズレる事故が起きうる。

### 規律 1: `F("count") ± 1` で原子更新

```python
User.objects.filter(pk=instance.follower_id).update(
    following_count=F("following_count") + 1,
)
```

`User.objects.get(pk=...).following_count += 1; save()` は read-modify-write で race する。`F()` で DB 側の 1 文に落とすのが必須。Rails AR の `increment_counter` 相当だが、`F()` の方が複雑な式 / 条件 update に拡張可能。

### 規律 2: `manage.py recount_<model>_stats` を最初から用意

```python
# instagram/backend/accounts/management/commands/recount_user_stats.py
class Command(BaseCommand):
    def add_arguments(self, parser):
        parser.add_argument("--dry-run", action="store_true")

    def handle(self, *args, dry_run=False, **opts):
        users = User.objects.annotate(
            true_followers=Count("follower_edges", distinct=True),
            true_posts=Count("posts",
                             filter=Q(posts__deleted_at__isnull=True),
                             distinct=True),
            ...
        )
        # 真値 vs 現在値 を比較、差分があれば update
```

夜間 batch (cron / EventBridge) から呼ぶ前提。**`--dry-run` で差分だけ表示できる**ようにしておくと運用での恐怖が減る (本番で「いきなり書き戻す」は怖い)。Rails の `rake task` 相当だが、Django の `BaseCommand` は argparse 統合と stdout/style helper が標準で付く。

### 規律 3: 「signal 落ちは起きる前提」で書く

signal は transaction の中で発火するが、Celery task が転んで再投入忘れだったり、デプロイ中の race だったりで drift する。「絶対ズレない」を目指すより「**ズレを定期的に検知 + 修復する経路を持つ**」方が運用が楽。**eventual consistency の精神**そのもの。

実例: `instagram/backend/accounts/management/commands/recount_user_stats.py`。

---

## 12. 内部 ingress shared secret の言語横断パターン (Django ↔ FastAPI)

§7 で github の Rails ↔ Python ai-worker の **内部 trusted ingress** を扱ったが、instagram では **Django ↔ FastAPI** で同じ pattern を逆向きに適用した (Django が呼ぶ側、ai-worker が受ける側)。

```python
# instagram/ai-worker/main.py
INTERNAL_TOKEN = os.environ.get("INTERNAL_TOKEN", "dev-internal-token")

def require_internal_token(
    x_internal_token: str | None = Header(default=None, alias="X-Internal-Token"),
):
    if x_internal_token != INTERNAL_TOKEN:
        raise HTTPException(status_code=401, detail="invalid internal token")

@app.post("/recommend", dependencies=[Depends(require_internal_token)])
def recommend(...): ...
```

Django 側は呼び出し共通関数で `X-Internal-Token` を自動付与:

```python
def _ai_post(path, payload):
    return requests.post(
        f"{settings.AI_WORKER_URL}{path}",
        json=payload,
        headers={"X-Internal-Token": settings.AI_WORKER_INTERNAL_TOKEN},
        timeout=5,
    )
```

**意図** (§7 と共通):
- ai-worker は VPC 内 / loopback 前提だが defense in depth として token を持つ
- 本番では Secrets Manager 経由の同じ強い値、ローカルは default literal `dev-internal-token`
- `/health` だけは ALB / Service Discovery health check 用に open
- timing attack を気にするなら `secrets.compare_digest(...)` (Python) / `ActiveSupport::SecurityUtils.secure_compare` (Ruby) を使うのが筋

実例: `instagram/ai-worker/main.py` + `instagram/backend/posts/views.py:_ai_post`。

---

## 13. single-process Hub goroutine + CSP fan-out (discord)

slack の **ActionCable + Redis pub/sub** (Rails / 規律 §2 + §10 と同じ「fan-out」だが realtime 寄り) と並ぶ、**3 番目の fan-out 実装パターン** を Go で確立した。Discord プロジェクト ([ADR 0001](../discord/docs/adr/0001-guild-sharding-single-process-hub.md) / [0002](../discord/docs/adr/0002-hub-goroutine-channel-pattern.md)) の運用知。

「**realtime fan-out を Redis pub/sub なしで書きたい**」ときに使う。Slack/Discord/Reddit の chat 系領域では、**プロセスを跨ぐ pub/sub の代わりに「per-shard Hub goroutine」で十分**になることが多い。

### 規律 1: shard キー = ドメインの自然な境界

global Hub にせず、**ドメインの自然な境界 (Discord ならギルド ID / slack ならワークスペース ID)** で Hub を分ける。`HubRegistry` (`map[shardKey]*Hub` + lazy 起動) で管理する。

```go
type Registry struct {
    mu   sync.Mutex
    hubs map[int64]*Hub      // guild_id -> Hub
    ctx  context.Context
}
func (r *Registry) GetOrCreate(guildID int64) *Hub {
    r.mu.Lock(); defer r.mu.Unlock()
    if h, ok := r.hubs[guildID]; ok { return h }
    h := NewHub(guildID, ...)
    go h.Run(r.ctx)
    r.hubs[guildID] = h
    return h
}
```

**意図**: 「1 broadcast = 1 ギルド分の subscriber 全員」が業務上の自然な単位。global Hub は他ギルドへの fan-out に巻き込まれて O(全 online user) で重くなる。per-channel まで切ると Hub 数が爆発するので **ギルド粒度がバランス点**。

### 規律 2: Hub goroutine が状態の唯一の owner (mutex なし)

`clients map` / `presence map` は **Hub.Run goroutine 専有**。外部からは `register chan` / `unregister chan` / `broadcast chan` 経由でしか触らせない。

```go
func (h *Hub) Run(ctx context.Context) {
    for {
        select {
        case c := <-h.register:    h.clients[c] = struct{}{}; h.fanoutPresence(c.UserID, "online")
        case c := <-h.unregister:  h.removeClient(c)
        case msg := <-h.broadcast: h.fanout(msg)
        case <-ticker.C:           h.checkHeartbeats()
        case <-ctx.Done():         return
        }
    }
}
```

**意図**: Rails ActionCable は thread + Redis subscribe が `clients` 集合を共有するが、Go では **CSP (`select` で全イベントを 1 goroutine に集約)** で書けるので **mutex を 1 つも持たずに race-free**。テスト時は `hub.RequestRegister(c) → time.Sleep(50ms) → assertion` で同期できる。

### 規律 3: non-blocking send + drop で slow consumer を吸収

`fanout` ループで `c.Send <- payload` を blocking で書くと **遅い 1 client が Hub 全体を止める**。`select { case ...: default: }` で drop し、後追いで unregister する。

```go
func (h *Hub) fanout(payload []byte) {
    var slow []*Client
    for c := range h.clients {
        if !c.trySend(payload) { slow = append(slow, c) }
    }
    for _, c := range slow { h.removeClient(c) }   // iterate 後に消す
}
```

**意図**: at-least-once は **保証しない** (再接続 + REST GET で取り直す前提)。WebSocket は再接続が前提なので、blocking で頑張るより **drop して unregister + 再接続誘導**のほうが Hub 全体のスループットを守れる。**fanout iterate 中に map を変更しない** ため、削除は iterate 後に遅延する規律も合わせて守る。

### 規律 4: heartbeat は **app 層 op + Hub 内 ticker**

WebSocket の ping/pong frame は **ブラウザ JS から送れない** (W3C WebSocket API の制限)。TCP keepalive は ALB / proxy で吸収されてアプリに見えない。**app 層で `op: 1` HEARTBEAT を定義し、Hub 内 ticker で最終受信時刻を見て evict** する形が一番素直。

```go
func (h *Hub) checkHeartbeats() {
    cutoff := time.Now().Add(-h.HeartbeatInterval * 3 / 2).UnixNano()
    for c := range h.clients {
        if c.LastHB.Load() < cutoff { h.removeClient(c) }   // presence offline 連動
    }
}
```

**意図**: ADR 0003。`LastHB` は `atomic.Int64` で readPump (write) と Hub goroutine (read) の cross-goroutine read を許容。`HeartbeatInterval * 1.5` の cutoff で「1 回 missed なら待つ、2 回連続なら殺す」の余裕。

### 規律 5: presence の同一 user 複数タブは **counted-conns**

同じ user が 2 タブ開いたとき、**「1 タブ閉じただけで offline」になると体感が壊れる**。Hub の `presence map` は `user_id -> {username, conns}` として **接続数を数え**、`conns == 0` になった瞬間だけ offline broadcast する。

```go
type presenceEntry struct { username string; conns int }

// register
if entry, ok := h.presence[c.UserID]; ok {
    entry.conns++                           // 既に online、broadcast しない
} else {
    h.fanoutPresence(c.UserID, "online")    // 初接続のみ
    h.presence[c.UserID] = &presenceEntry{username: c.Username, conns: 1}
}
// unregister: entry.conns--; if entry.conns <= 0 { delete + offline broadcast }
```

**意図**: ADR 0003。テストは `TestHubMultiTabPresence` で「2 タブ→ 1 タブ閉じても offline 0 件、2 タブ目閉じて offline 1 件」を縛る。

### この規律を守るテスト (Go の流儀)

「state owner が 1 goroutine」だと **chan に送る → 観測** で同期テストが書ける。`go test -race` を必須化して mutex を持たない設計の正しさを CI で検証する:

| テスト | 検証内容 |
| --- | --- |
| `TestHubBroadcastReachesRegisteredClient` | fan-out: 全 client に DISPATCH が届く |
| `TestHubUnregisterStopsBroadcast` | unregister 後に届かない |
| `TestHubHeartbeatTimeoutEvictsClient` | LastHB を過去にして ticker で evict (規律 4) |
| `TestHubSlowConsumerDropped` | buffer=1 + flood で drop + close (規律 3) |
| `TestHubMultiTabPresence` | counted-conns (規律 5) |

実例: `discord/backend/internal/gateway/hub.go` + `hub_test.go`、`discord/backend/internal/gateway/registry.go`。

### 派生 ADR で扱う候補 (本パターンの拡張点)

- **multi-process shard 化**: 1 万 guild が active になったら 1 プロセスで持ちきれない → consistent hashing + Redis pub/sub (slack ActionCable 寄りの形に戻る)
- **inactive Hub の lazy 停止**: 空 client が一定時間続いたら Hub 自身が registry から自分を抜く
- **at-least-once delivery**: drop の代わりに transactional outbox + replay token

「**いつ goroutine + channel で足りなくなるか**」を ADR で先に書いておくと、shard 化が必要になったときに迷わない。

---

## 関連ドキュメント

- [CLAUDE.md](../CLAUDE.md) — エージェント向け要約
- [service-architecture-lab-policy.md](service-architecture-lab-policy.md) — 完成定義・スコープ・ADR・プロジェクト詳細
- [api-style.md](api-style.md) — REST/GraphQL の選定方針
- [framework-django-vs-rails.md](framework-django-vs-rails.md) — Django ↔ Rails 比較
- [coding-rules/rails.md](coding-rules/rails.md) — Service オブジェクト / ai-worker 境界 / job 原子性
- [coding-rules/python.md](coding-rules/python.md) — Django/DRF + ai-worker (FastAPI) のコーディング規約
- [testing-strategy.md](testing-strategy.md) — RSpec / pytest-django / OpenAPI 契約検証
- [git-workflow.md](git-workflow.md) — ブランチ戦略 / コミット規約
