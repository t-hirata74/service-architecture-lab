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

## 関連ドキュメント

- [CLAUDE.md](../CLAUDE.md) — 全体方針 / スコープ / ADR の意義
- [api-style.md](api-style.md) — REST/GraphQL の選定方針
- [coding-rules/rails.md](coding-rules/rails.md) — Service オブジェクト / ai-worker 境界 / job 原子性
- [testing-strategy.md](testing-strategy.md) — RSpec / FactoryBot / OpenAPI 契約検証
- [git-workflow.md](git-workflow.md) — ブランチ戦略 / コミット規約
