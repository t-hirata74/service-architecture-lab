# ADR 0005: ブラウザ E2E に Playwright を採用する

## ステータス

Accepted（2026-04-30）

## コンテキスト

Slack 風プロジェクトの**技術課題の中核**は以下である：

- WebSocket fan-out によるリアルタイムメッセージ配信（ADR 0001）
- 既読 cursor の多デバイス同期（ADR 0002）

これらは「**複数クライアントが同時に動作している状態**」でしか正しさを証明できない。Rails の単体・統合テスト（minitest）では「broadcast が呼ばれた」までは検証できるが、「**ブラウザ A で送信 → ブラウザ B で受信される**」までは到達できない。

加えて、本リポジトリの趣旨はポートフォリオ強化を含むため、「**実際にブラウザで動いている**」ことを E2E テストおよび録画・スクショで示せると訴求力が大きく上がる。

## 決定

ブラウザ E2E テストフレームワークとして **Playwright** を採用する。配置は `slack/playwright/` 配下とする。

```text
slack/playwright/
  tests/
    auth.spec.ts
    messaging.spec.ts        # 2 BrowserContext で送信 → 受信を検証
    read-sync.spec.ts
  playwright.config.ts
  package.json
```

役割分担：

| レイヤー | フレームワーク | 範囲 |
| --- | --- | --- |
| 単体・統合 | minitest（Rails 標準） | モデル / コントローラ / ActionCable Channel |
| ブラウザ E2E | **Playwright** | ログイン → チャンネル → メッセージ送信 → リアルタイム受信 |

両者の役割は混ぜない。

## 検討した選択肢

### 1. Playwright ← 採用

- **複数 BrowserContext** を1テスト内で扱える ⇒「A 送信 → B 受信」が自然に書ける
- **auto-wait** 機構で flaky テストが減る
- **trace viewer / 録画 / スクショ**が標準装備
- **Chromium / Firefox / WebKit** 全部対応
- 公式に TypeScript ファースト
- 近年デファクト化しており実務でも採用が多い

### 2. Cypress

- 直感的な DSL、デバッグ体験は良い
- ただし **複数タブ・複数ドメイン**の扱いに歴史的な制約があり、リアルタイム fan-out テストでは不利
- WebSocket の検証方法が Playwright より遠回りになる
- 本プロジェクトの中核要件と相性が悪い

### 3. Selenium WebDriver

- 古くから使われており実績は最大
- ただし API が古く、auto-wait なし、書き味が現代的でない
- 学習価値も「現代の選択肢」を学ぶ観点では低い

### 4. minitest + Capybara

- Rails の system test として標準
- ただし API モード Rails では別途セットアップが要る
- WebKit / Firefox 横断や複数 BrowserContext は得意ではない
- Frontend (Next.js) を別プロジェクトとして扱う本構成では Rails 内部に閉じ込める意味が薄い

### 5. E2E テストを書かない

- 単体・統合だけで済ます
- 本プロジェクトの中核技術課題（リアルタイム fan-out、多デバイス既読同期）を**コード上で証明できない**ため不採用
- ポートフォリオ価値も大幅に下がる

## 採用理由

- **本プロジェクトの技術課題と相性が最良**：複数 BrowserContext が言語仕様レベルで自然に扱える
- **WebSocket 越しのリアルタイム配信を E2E で証明できる**：単体テストでは到達不可能な領域
- **ポートフォリオ価値**：trace viewer の動画 / GIF を README に貼れる
- **ツールチェーンの近代性**：TypeScript ファースト、auto-wait、Playwright Inspector などモダンな開発体験
- **採用例が多い**：Microsoft 製、業界デファクト寄り

## 却下理由

- **Cypress**：複数タブ / クロスドメインの制約が本プロジェクトの中核要件に直撃
- **Selenium**：書き味が古く、学習価値も相対的に低い
- **Capybara**：API モード Rails + 別プロジェクトの Next.js 構成では旨味が薄い
- **E2E なし**：技術課題を証明できず、ポートフォリオ価値も毀損

## 引き受けるトレードオフ

- **ツールチェーン肥大化**：Node.js + ブラウザバイナリ（数百 MB）が必要。`npx playwright install` で導入する手順が増える
- **テスト実行時間**：単体・統合より明確に遅い（1テスト 数秒〜十数秒）。CI に乗せる際は単体と分離して並列化する設計が必要（将来 ADR 検討）
- **メンテコスト**：UI 変更で selector を直す必要がある。Page Object パターンで吸収する
- **JWT 認証フローの再現**：UI 越しのログインフローは毎テスト走らせると遅いので、`storageState` を使った認証セッションキャッシュを採用する（実装時に詳細決定）

## ディレクトリ命名

`e2e/` ではなく `playwright/` を採用する。

理由：
- 中身が一目で分かる（reviewer 視点での情報量が多い）
- 本プロジェクト規模ではツール乗り換えは現実的に発生しない
- 学習・ポートフォリオ用途では「使った技術が即わかる」優先で良い

## 関連 ADR

- ADR 0001: リアルタイム配信方式（fan-out のテスト対象）
- ADR 0002: 既読 cursor 整合性（多デバイス同期のテスト対象）
- ADR 0004: 認証方式（E2E では JWT を `storageState` でキャッシュする方針）

## 参考

- Playwright 公式: https://playwright.dev/
- Playwright vs Cypress 比較: https://playwright.dev/docs/why-playwright
