# figma E2E (Playwright)

2 BrowserContext (alice / bob) で同一 document を開き、**op が ActionCable (Solid Cable) で
fan-out されて双方の canvas が同一状態に収束する**ことを実機フルスタックで確認する
(MySQL + Rails dev + ai-worker + Next.js production build)。

## 実行

```sh
# 依存 (MySQL :3328) を起動しておく
cd figma && docker compose up -d mysql && cd backend && bin/rails db:prepare && cd ../playwright

npm ci
npx playwright install chromium
npm test          # webServer が Rails / ai-worker / Next を自動起動
```

`playwright.config.ts` の webServer がバックエンド (rbenv shims を PATH に注入して Ruby 4.0.5 で
`rails s`)・ai-worker (`.venv/bin/uvicorn`)・frontend (`npm run start`) を起動する。
`reuseExistingServer: true` なので既に起動済みなら再利用する。

## シナリオ

| test | 検証 |
| --- | --- |
| op fan-out | alice 矩形追加 → bob に出現 / bob 楕円追加 → alice に出現 (双方向) / bob 削除 → alice も収束 |
| viewer 制限 | viewer role は編集ボタン無効 (op 投入不可、ADR 0004) |

## gif 録画

```sh
npm run capture   # PLAYWRIGHT_VIDEO=on で録画 → ffmpeg で alice|bob を hstack → captures/*.gif
```

`PLAYWRIGHT_VIDEO=on` のときだけ各操作後に小休止を挟み、図形の出現/消失を視認できるようにする
(CI では無効なので CI は速いまま)。ffmpeg 必須。
