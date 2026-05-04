# reddit/playwright

Reddit プロジェクトの E2E テスト。chromium で 3 シナリオ:

1. **anonymous 閲覧**: 未ログインで subreddit 一覧が見える
2. **認証フロー**: 登録 → subreddit 作成 → post 作成 → upvote → コメント → 返信 (depth 2 で path が更新される)
3. **ai-worker proxy**: post 詳細で TL;DR ボタン → 要約と keywords が表示される

## キャプチャ

各シナリオの実行を `npm run capture` で gif にして `captures/` に置く (Playwright が録画した webm を ffmpeg で変換)。

| # | シナリオ | キャプチャ |
| --- | --- | --- |
| 01 | anonymous 閲覧 | ![](captures/01-anonymous-feed.gif) |
| 02 | 認証フロー | ![](captures/02-auth-flow.gif) |
| 03 | ai-worker proxy | ![](captures/03-ai-summarize.gif) |

## 前提

- backend/.venv と ai-worker/.venv が `pip install -r requirements.txt` 済み
- frontend で `npm install` 済み
- ffmpeg (`brew install ffmpeg`) — `npm run capture` 時のみ

## 実行

```bash
cd reddit/playwright
npm install
npx playwright install chromium

npm test                # E2E (失敗時のみ録画)
npm run capture         # 常時録画 + gif 化 (captures/*.gif を再生成)
```

`playwright.config.ts` の `webServer` が backend / ai-worker / frontend を自動起動する。
DB は `./e2e.db` (sqlite) を使用し、テスト開始前に削除して migrate からやり直す。

## キャプチャ生成の仕組み

- `playwright.config.ts` は `PLAYWRIGHT_VIDEO=on` のときだけ全ケース録画 (`video: "on"`)
- `scripts/record-captures.sh` が test 実行 → `test-results/<dir>/video.webm` を発見 → ffmpeg で `fps=10, width=720px, palettegen + paletteuse` の gif に変換
- 出力名は test ディレクトリ名から content match (`*anonymous*` `*認証フロー*` `*ai-worker*`) して `01-..03-` の prefix を付ける。テストを増やしたら `scripts/record-captures.sh` の `case` 句に追加する

## CI と連動

GitHub Actions `reddit-playwright-e2e` ジョブが PR / push 毎に **full E2E + capture** を回し、以下 3 つを **artifact として upload**:

| artifact 名 | 内容 | retention |
| --- | --- | --- |
| `reddit-captures` | `captures/*.gif` (README 埋め込み相当) | 30 日 |
| `reddit-playwright-test-results` | `test-results/` (webm + trace、失敗解析用) | 7 日 |
| `reddit-playwright-report` | `playwright-report/` (HTML report) | 7 日 |

Actions の Run 詳細ページから download できる。レビュー時に **「最新コードで撮った gif」** を確認できる位置づけ。

リポジトリ内の `reddit/playwright/captures/*.gif` (README 表示用) は **手動更新** (`npm run capture` + commit) のまま。CI は git に書き戻さない (gif は非決定的なので `git diff --exit-code` 不可、auto-commit はノイズ大)。

別の `reddit-playwright` ジョブ (typecheck only) は速い gate として残してある。
