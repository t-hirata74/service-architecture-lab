# テスト戦略

## 基本方針

- **テストは「サービス固有の技術課題が壊れていないか」を守るために書く**。網羅率は目標にしない
- 単体 / 結合 / E2E をレイヤーごとに **重複させずに役割分担** させる
- 「ローカルでブラウザから動作確認できる」ことを完成の定義に含める（CLAUDE.md）。E2E はその担保

---

## レイヤーと責務

| レイヤー | フレームワーク | カバーする範囲 |
| --- | --- | --- |
| Backend 単体 / 結合 | minitest (Rails 標準) | モデル不変条件、controller の入出力、ActionCable 購読 / broadcast |
| Frontend 単体 | （現状なし） | 必要になれば Vitest + React Testing Library を追加 |
| Python 単体 | （現状なし） | ロジックが増えたら pytest を追加 |
| ブラウザ E2E | Playwright | ログインから複数ユーザー / 複数タブを跨ぐ実シナリオ |

E2E が他レイヤーで証明できることを再検証しない。逆に **マルチユーザー / リアルタイム性 / 既読同期** は E2E でしか出ない。

---

## Backend (Rails minitest)

ディレクトリは Rails 標準:

```text
slack/backend/test/
  models/
  controllers/
  channels/             # ActionCable channel テスト
  integration/          # broadcast / 多モデル横断
  fixtures/             # YAML fixtures
  test_helper.rb
```

### 書くもの

- **モデルの不変条件**：例「既読 cursor は単調増加」「論理削除されたメッセージは `active` スコープで除外」
- **Controller の入出力**：認証エラー / 権限 / バリデーション。シリアライズ結果のキー
- **ActionCable**：subscribe 拒否 / 確立 / streaming target / broadcast 内容
- **Integration**：「メッセージ POST → broadcast される」「既読 cursor 進む → UserChannel に流れる」

### 書かないもの

- フレームワーク自体の挙動（Rails の `validates :name, presence: true` を再検証する等）
- 一時的なログ出力 / デバッグ目的のテスト
- 過度なエッジケース（null / 巨大文字列 / 異常型）の網羅

### 実行

```bash
cd slack/backend
bundle exec rails test                    # 全件
bundle exec rails test test/integration   # 一部
```

並列実行は `test_helper.rb` で有効化済み。

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

- backend: MySQL + Redis サービス起動 → `db:create db:migrate` → `rails test`
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
