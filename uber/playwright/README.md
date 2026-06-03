# Uber — Playwright E2E

backend の **非対称な 2 経路 (rider=REST poll / driver=WebSocket)** が 1 つの trip で
出会う様子を **2 BrowserContext** で観測する。ADR 0002 (trip + driver state machine /
compare-and-set) と ADR 0003 (per-cell matcher goroutine + channel offer) が
ブラウザ越しに守られていることを確認する。

## tests

| spec | 検証 |
| --- | --- |
| `dispatch.spec.ts :: ride dispatch` | driver が渋谷で go online (WS) → rider が渋谷→新宿で配車要求 (REST) → 同一 H3 cell の matcher が driver に offer → accept → rider の poll が `driver_accepted` と担当 driver id を観測 |
| `dispatch.spec.ts :: rider cancel` | driver 不在の cell (東京駅) で配車要求 → `matching` のまま → rider が cancel → `canceled` に遷移 (REST cancel 経路 + state machine) |

## 起動

```bash
# 依存 (mysql:3327 / ai-worker:8100) を起動
docker compose -f ../docker-compose.yml up -d mysql ai-worker

# backend (Go) は host に go があれば playwright の webServer が自動起動する。
# go が無い環境では先に :3110 を立てておけば reuseExistingServer で再利用される。
cd ../backend && go run ./cmd/migrate && \
  HTTP_ADDR=127.0.0.1:3110 AI_WORKER_URL=http://localhost:8100 \
  AI_INTERNAL_TOKEN=dev-internal-token go run ./cmd/dispatch

# frontend
cd ../frontend && npm install && npm run dev

# playwright
cd ../playwright && npm install && npx playwright install --with-deps chromium
npm test          # 実行
npm run capture   # gif 録画 (captures/*.gif、ffmpeg 必須)
```

Playwright の `webServer` で backend / ai-worker / frontend を自動起動する
(`reuseExistingServer: true` なので、既に立っていれば再利用)。

## captures

| gif | 見どころ |
| --- | --- |
| `captures/01-dispatch-offer-accept.gif` | driver(WS) \| rider(REST) を hstack。offer → accept → driver_accepted |
| `captures/02-rider-cancel-matching.gif` | matching → cancel → canceled |
