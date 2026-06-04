import { test, expect, type APIRequestContext } from "@playwright/test";

const BACKEND = "http://127.0.0.1:3130";
const API_KEY = "dev-ingest-key";

async function registerUser(api: APIRequestContext, email: string): Promise<string> {
  const res = await api.post(`${BACKEND}/auth/register`, {
    headers: { "Content-Type": "application/json" },
    data: { email, password: "supersecret123" },
  });
  if (!res.ok()) throw new Error(`register failed: ${res.status()} ${await res.text()}`);
  return (await res.json()).token as string;
}

// 過去の閉じた窓に入るよう ts を少し過去にして ingest する (WINDOW_SECONDS=1 なので即 flush 対象)。
async function ingest(api: APIRequestContext, metric: string, host: string, values: number[]) {
  const now = Math.floor(Date.now() / 1000);
  const samples = values.map((v, i) => ({
    name: metric,
    tags: { host },
    type: "gauge",
    value: v,
    ts: new Date((now - 3 + (i % 2)) * 1000).toISOString(),
  }));
  const res = await api.post(`${BACKEND}/ingest`, {
    headers: { "Content-Type": "application/json", "X-API-Key": API_KEY },
    data: { samples },
  });
  if (res.status() !== 202) throw new Error(`ingest failed: ${res.status()} ${await res.text()}`);
}

// ingest → 固定窓 rollup flush → dashboard のチャートに点が表示される (観測ループ全体)。
test("ingest したメトリクスが dashboard のチャートに表示される", async ({ page, playwright }) => {
  const api = await playwright.request.newContext();
  const ts = Date.now();
  const token = await registerUser(api, `viewer-${ts}@example.com`);

  await ingest(api, "cpu.load", "web1", [0.4, 0.6, 0.5, 0.7]);

  await page.addInitScript((t) => localStorage.setItem("datadog_jwt", t as string), token);
  await page.goto("/dashboard");

  // flush + poll を待って metric ボタンとチャートの点が出る
  await expect(page.getByTestId("metric-cpu.load")).toBeVisible({ timeout: 20_000 });
  await page.getByTestId("metric-cpu.load").click();
  await expect(page.locator('[data-testid="datapoint"]').first()).toBeVisible({ timeout: 20_000 });
  expect(await page.locator('[data-testid="datapoint"]').count()).toBeGreaterThan(0);

  if (process.env.PLAYWRIGHT_VIDEO === "on") await page.waitForTimeout(2500); // gif 用に表示を保持

  await api.dispose();
});

// alert rule (gt) が breach で firing になり、/alerts/events に記録される (API レベルで検証)。
test("閾値超過で alert が firing になる", async ({ playwright }) => {
  const api = await playwright.request.newContext();
  const ts = Date.now();
  const token = await registerUser(api, `alerter-${ts}@example.com`);
  const auth = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };

  // rule: latency.ms の avg が 100 超で即発火 (for_s=0)
  const ruleRes = await api.post(`${BACKEND}/alerts/rules`, {
    headers: auth,
    data: { name: "latency high", metric_name: "latency.ms", comparator: "gt", threshold: 100, window_s: 60, for_s: 0, agg: "avg" },
  });
  expect(ruleRes.status()).toBe(201);
  const ruleID = (await ruleRes.json()).id as number;

  await ingest(api, "latency.ms", "web1", [300, 320, 310, 305]); // breach

  // flush(~1s) + eval(~1s) を待ち、firing イベントを poll
  let firing = false;
  for (let i = 0; i < 30; i++) {
    const ev = await api.get(`${BACKEND}/alerts/events?limit=50`, { headers: auth });
    const events = ((await ev.json()).events ?? []) as { rule_id: number; state: string }[];
    if (events.some((e) => e.rule_id === ruleID && e.state === "firing")) {
      firing = true;
      break;
    }
    await new Promise((r) => setTimeout(r, 500));
  }
  expect(firing).toBe(true);

  await api.dispose();
});
