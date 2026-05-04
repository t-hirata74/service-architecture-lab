# reddit/playwright

Reddit プロジェクトの E2E テスト。chromium で 3 シナリオ:

1. **anonymous 閲覧**: 未ログインで subreddit 一覧が見える
2. **認証フロー**: 登録 → subreddit 作成 → post 作成 → upvote → コメント → 返信 (depth 2 で path が更新される)
3. **ai-worker proxy**: post 詳細で TL;DR ボタン → 要約と keywords が表示される

## 前提

- backend/.venv と ai-worker/.venv が `pip install -r requirements.txt` 済み
- frontend で `npm install` 済み

## 起動

```bash
cd reddit/playwright
npm install
npx playwright install chromium
npm test
```

`playwright.config.ts` の `webServer` が backend / ai-worker / frontend を自動起動する。
DB は `./e2e.db` (sqlite) を使用し、テスト開始前に削除して migrate からやり直す。
