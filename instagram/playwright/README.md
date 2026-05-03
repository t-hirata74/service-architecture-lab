# instagram Playwright E2E

ローカルで E2E を回すには、依存サービスを先に立てる:

```bash
cd ../
docker compose up -d mysql redis    # 3311 / 6380
```

Playwright が backend / ai-worker / frontend を `webServer` 経由で自動起動する。
backend は **`CELERY_TASK_ALWAYS_EAGER=True`** で起動するので Celery worker は
不要 (fan-out / backfill / unfollow remove / delete propagation すべて Django
プロセス内で同期実行される)。

```bash
npm install
npx playwright install chromium
npm test
```

## CI

GitHub Actions ではジョブを `instagram-backend` と分けるが、Playwright 自体は
**Phase 5 で scaffold のみ**として置き、CI で playwright test を回すのは派生
タスクで扱う (perplexity と同じ規律)。
