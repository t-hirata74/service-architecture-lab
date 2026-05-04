# Discord — Playwright E2E

ADR 0001 (per-guild Hub) と ADR 0002 (goroutine + channel) が守られていることを **2 BrowserContext** から WebSocket fan-out で観測する。

## tests

| spec | 検証 |
| --- | --- |
| `fanout.spec.ts :: WebSocket fan-out` | alice / bob 別 context で同 guild に join。alice 投稿 → bob に MESSAGE_CREATE が WebSocket 経由で届く / 双方向で伝播 / presence pane に相手が online で出る |
| `fanout.spec.ts :: presence offline` | bob の context.close() → alice の presence pane から bob が消える (ADR 0003 の offline broadcast) |

## 起動

```bash
# 初回のみ
docker compose -f ../docker-compose.yml up -d mysql
cd ../backend && go run ./cmd/server/migrate
cd ../ai-worker && python -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt
cd ../frontend && npm install
cd ../playwright && npm install && npx playwright install --with-deps chromium

# 走らせる
npm test
```

Playwright の `webServer` で backend / ai-worker / frontend を自動起動する。
**HEARTBEAT_INTERVAL_MS=2000** に短縮しているので、heartbeat タイムアウト系の挙動も
秒単位で観測できる (production は 10000ms、ADR 0003)。
