# datadog E2E (Playwright)

実機フルスタック（MySQL + Go backend + Next.js dashboard）で **観測ループ全体**を検証する:
`ingest (API key) → 固定窓 rollup flush → /query → dashboard チャート表示`、および
`alert rule (gt) → breach → firing` を確認する。

E2E は flush/eval を速くするため `WINDOW_SECONDS=1` / `EVAL_INTERVAL_SEC=1` で backend を起動する。

## 実行

```sh
cd datadog && docker compose up -d mysql && cd playwright
npm ci && npx playwright install chromium
npm test
```

`playwright.config.ts` の webServer が backend（local は docker `golang:1.25` で `go run`、CI は
setup-go の native go）と frontend（`npm run start`）を起動する。`reuseExistingServer: true`。

## シナリオ

| test | 検証 |
| --- | --- |
| dashboard チャート | ingest → rollup flush → dashboard の metric ボタン + チャートの datapoint が表示される |
| alert firing | rule(gt, threshold 100, for_s 0) + breach ingest → `/alerts/events` に firing 記録 (API 検証) |

## gif 録画

```sh
npm run capture   # PLAYWRIGHT_VIDEO=on で録画 → ffmpeg → captures/01-dashboard.gif
```
