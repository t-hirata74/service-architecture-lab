# テスト戦略

## 基本方針

- **テストは「サービス固有の技術課題が壊れていないか」を守るために書く**。網羅率は目標にしない
- 単体 / 結合 / E2E をレイヤーごとに **重複させずに役割分担** させる
- 「ローカルでブラウザから動作確認できる」ことを完成の定義に含める（CLAUDE.md）。E2E はその担保

---

## レイヤーと責務

| レイヤー | フレームワーク | カバーする範囲 |
| --- | --- | --- |
| Backend 単体 / 結合 | **RSpec (rspec-rails) + FactoryBot** | モデル不変条件、controller の入出力、ActionCable 購読 / broadcast |
| Frontend 単体 | （現状なし） | 必要になれば Vitest + React Testing Library を追加 |
| Python 単体 | （現状なし） | ロジックが増えたら pytest を追加 |
| ブラウザ E2E | Playwright | ログインから複数ユーザー / 複数タブを跨ぐ実シナリオ |

E2E が他レイヤーで証明できることを再検証しない。逆に **マルチユーザー / リアルタイム性 / 既読同期** は E2E でしか出ない。

---

## Backend (Rails RSpec)

**共通方針**: Rails backend は RSpec + FactoryBot で運用する。
ディレクトリは rspec-rails 標準:

```text
<service>/backend/spec/
  models/
  requests/             # Controller / API の入出力 (旧 integration / controllers)
  channels/             # ActionCable channel スペック
  jobs/                 # ActiveJob スペック
  factories/            # FactoryBot 定義 (旧 fixtures/*.yml の代わり)
  rails_helper.rb
  spec_helper.rb
```

### 書くもの

- **モデルの不変条件**：例「既読 cursor は単調増加」「アップロード状態機械は不正遷移を拒否」
- **Request 仕様**：認証エラー / 権限 / バリデーション。シリアライズ結果のキー
- **ActionCable**：subscribe 拒否 / 確立 / streaming target / broadcast 内容
- **Integration**：「メッセージ POST → broadcast される」「既読 cursor 進む → UserChannel に流れる」「アップロード → enqueue される」

### 書かないもの

- フレームワーク自体の挙動（Rails の `validates :name, presence: true` を再検証する等）
- 一時的なログ出力 / デバッグ目的のスペック
- 過度なエッジケース（null / 巨大文字列 / 異常型）の網羅

### 実行

```bash
cd <service>/backend
bundle exec rspec                        # 全件
bundle exec rspec spec/requests          # 一部
bundle exec rspec spec/models/video_spec.rb:42   # 行指定
```

### 既存 minitest の扱い

- `slack/backend` は当初 minitest で実装済み。**次に slack に手を入れる時に RSpec へ移行する**
- 新規 / 進行中の Rails backend (`youtube/backend` 等) は最初から RSpec で書く

### Style

- 1 example = 1 振る舞い。`describe` / `context` / `it` で読みやすい階層を作る
- `let` / `let!` は最小限。値が見えなくなる過剰なネストはしない
- `subject` は対象の振る舞いを命名する時のみ使う（`is_expected.to ...` で短くなる時）
- FactoryBot trait を使って状態のバリエーションを表現（例: `:transcoding`, `:published`）

### 実装中に出た落とし穴（リポジトリ固有）

#### MySQL FULLTEXT (ngram) は transactional fixtures だと検索ヒットしない

InnoDB FULLTEXT は **commit 後にしか index に反映されない**。RSpec デフォルトの
`use_transactional_fixtures = true` だと、example 内で `create` した行が
`MATCH ... AGAINST ...` でヒットせず、結果が空になる。

回避策（spec ファイル単位で適用）:

```ruby
RSpec.describe "Videos search", type: :request do
  self.use_transactional_tests = false

  before(:all) do
    [Video, User, Tag, VideoTag].each(&:delete_all)
    @v1 = create(:video, :published, title: "...")
    ...
  end
  after(:all) do
    [Video, User, Tag, VideoTag].each(&:delete_all)
  end
end
```

#### `enqueue_after_transaction_commit` は **ApplicationJob 側に書く**

Rails 8.1 で `config.active_job.enqueue_after_transaction_commit` の **global 指定が deprecated**。
state machine + enqueue の原子性を担保するなら、`app/jobs/application_job.rb` に:

```ruby
class ApplicationJob < ActiveJob::Base
  self.enqueue_after_transaction_commit = true
end
```

詳細は [`coding-rules/rails.md`](coding-rules/rails.md) の「Job の原子的 enqueue」を参照。

#### Active Storage の `analyze_later` がテストログに ffmpeg エラーを残す

ダミーの `StringIO.new("fake-bytes")` を `attach` すると、Active Storage が
動画メタデータ抽出ジョブを enqueue し、ffmpeg が `moov atom not found` で
失敗する。**動作としては無害**（仕様）。ログを抑制したい場合は
`config.active_storage.analyze_later = false` を test 環境に設定するか、
`Video.original.analyze` を呼び出さないテストデータを使う。

#### WebMock は ai-worker 境界の HTTP 越境を遮断する

`spec/rails_helper.rb`:

```ruby
WebMock.disable_net_connect!(allow_localhost: true)
```

これで実 ai-worker への HTTP コールが起きないことを保証する。各 spec で
`stub_request(:post, "#{base}/...")` を明示する。詳細は
[`coding-rules/rails.md`](coding-rules/rails.md) の「ai-worker 境界（共通方針）」を参照。

### OpenAPI 契約検証

REST + OpenAPI を採用するプロジェクト（slack / youtube）では、request spec が
`backend/docs/openapi.yml` のスキーマに **必ず一致**することを committee-rails で検証する。

```ruby
# spec/requests/videos_spec.rb
it "matches OpenAPI schema" do
  get "/videos"
  assert_response_schema_confirm  # committee-rails が openapi.yml と照合
end
```

詳細は [`api-style.md`](api-style.md) を参照。

---

## E2E (Playwright)

```text
slack/playwright/
  tests/
    auth.spec.ts
    realtime-fanout.spec.ts
    read-sync.spec.ts
    summary.spec.ts
    helpers.ts
  playwright.config.ts
```

### 書くもの

- **ブラウザを介さないと出ないシナリオのみ**:
  - ログイン / サインアップ / 未認証リダイレクト
  - 2 BrowserContext を立てて A から送信 → B にリアルタイム配信
  - 既読 cursor の自動進行が複数タブに同期される
  - ai-worker の要約ボタンから結果が表示される

### 設定の注意

- `fullyParallel: false` / `workers: 1`（DB を共有するので serial）
- backend (`:3010`) / frontend (`:3005`) を `webServer` で起動。`reuseExistingServer: true`
- ai-worker を要するスペックは `AI_WORKER_RUNNING=1` 環境変数でガード

### ヘルパ

`tests/helpers.ts` に以下を集約し、各 spec から import:

- `signupViaUI(page, email, password)`
- `loginViaUI(page, email, password)`
- `uniqueEmail()` / `uniqueChannelName()`（時刻 + ランダムで衝突回避）

各 spec で fresh user / channel を作る。fixture を共有しない。

### 実行

```bash
cd slack/playwright
npm test                              # 全件 (HTML reporter)
AI_WORKER_RUNNING=1 npm test          # ai-worker 必要なスペック含む
npx playwright test --ui              # デバッグ
```

---

## Python (ai-worker)

- 現状はモック実装のためテストなし
- ロジックを足したら `pytest` を導入し、CI に追加する
- 導入時は同時に `requirements-dev.txt` を分割

---

## Frontend (Next.js)

- 現状は **lint + 型チェックのみ**（Vitest 未導入）
- 「ロジックが UI から出てきたら」`lib/` レベルでユニットテストを足す。コンポーネント単体を片っ端から testing library で叩くことはしない

---

## CI でのテスト

`.github/workflows/ci.yml`:

- backend: MySQL (+ 必要に応じて Redis) サービス起動 → `db:create db:migrate` → `bundle exec rspec` (slack は移行までの間 `rails test`)
- frontend: `npm run lint` + `npx tsc --noEmit`
- ai-worker: import smoke + uvicorn boot + `/health`

E2E (Playwright) は **現状 CI で動かしていない**（ブラウザバイナリの取得が重い / 学習リポ）。  
将来動かす際は別ジョブで Chromium のみ・必要 spec のみに絞る。

---

## カバレッジ目標

- 数値目標は設定しない。代わりに **ADR で「これを壊さない」と宣言したものは必ずテストで縛る**:
  - ADR 0001 → fan-out E2E (`realtime-fanout.spec.ts`)
  - ADR 0002 → 既読 cursor 単調増加 (model test) + 同期 broadcast (integration test) + 多タブ同期 (E2E)
- ADR を新しく書いたら「これを守るテストはどれか」を ADR 内で言及する
