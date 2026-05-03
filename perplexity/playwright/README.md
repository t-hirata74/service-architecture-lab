# perplexity / playwright

ADR 0005 で予告した Playwright E2E. `fetch ReadableStream` で SSE を受信する実装が
ブラウザ越しでも壊れていないことを e2e で確認する目的.

## 前提

- backend (rails) / ai-worker (uvicorn) / frontend (next dev) の 3 つを `playwright.config.ts`
  の `webServer` ブロックが必要に応じて起動する (`reuseExistingServer: true`).
- backend には dev seeds (User id=1, sources / chunks) が投入済みであること.

## 起動

```bash
cd perplexity/playwright
npm install
npx playwright install chromium

# dev サーバを別 shell で起動済みなら playwright 単体で:
npm test

# headed (ブラウザを見ながら)
npm run test:headed

# UI モード (Playwright UI explorer)
npm run test:ui
```

## カバレッジ

| spec | 確認すること |
| --- | --- |
| `tests/query_stream.spec.ts` | POST /queries → stream_url 取得 → SSE chunk 受信 → 引用ボタン表示 → 完了バッジ |
| (同) | 空クエリで「エラー」バッジが出る (backend 400 or UI バリデーション) |

## 設計メモ

- `webServer` で 3 サービスを揃えるが、`reuseExistingServer: true` のため、開発時は
  既起動の dev server を流用する.
- ai-worker は `bash -lc` 経由で `.venv` を有効化している. CI で実行する場合は
  別途 venv を bootstrap するレイヤーを追加するか、Docker compose 経路に切り替える.
- SSE は数秒〜十数秒かかるため、`timeout: 60_000` を test-level で確保している (ADR 0003).
