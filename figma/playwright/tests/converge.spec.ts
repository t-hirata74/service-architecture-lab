import { test, expect, type APIRequestContext, type BrowserContext, type Page } from "@playwright/test";

const BACKEND = "http://127.0.0.1:3120";

async function signup(ctx: APIRequestContext, email: string, name: string) {
  const res = await ctx.post(`${BACKEND}/create-account`, {
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    data: { email, password: "supersecret123", name },
  });
  if (!res.ok()) throw new Error(`signup ${email} failed: ${res.status()} ${await res.text()}`);
  const token = res.headers()["authorization"];
  const me = await ctx.get(`${BACKEND}/me`, { headers: { Authorization: token } });
  return { token, id: (await me.json()).id as number };
}

async function openDoc(context: BrowserContext, token: string, docId: number): Promise<Page> {
  await context.addInitScript((t) => localStorage.setItem("figma_jwt", t as string), token);
  const page = await context.newPage();
  await page.goto(`/documents/${docId}`);
  await expect(page.getByTestId("canvas")).toBeVisible();
  // ActionCable subscription 確立を待つ (確立前の op 投入取りこぼし防止)。
  await expect(page.getByTestId("cable-status")).toHaveText("connected", { timeout: 20_000 });
  return page;
}

const shapes = (p: Page) => p.locator('[data-testid^="shape-"]');

// gif 録画時のみ各操作後に小休止を入れ、図形の出現/消失を視認できるようにする (CI では無効)。
const CAPTURING = process.env.PLAYWRIGHT_VIDEO === "on";
const beat = (p: Page, ms = 700) => (CAPTURING ? p.waitForTimeout(ms) : Promise.resolve());

// gif 録画時 (PLAYWRIGHT_VIDEO=on) のみ context 単位で video を撮る。
// 手動 newContext は fixture の video 設定が効かないため明示する (slack/discord と同方針)。
async function makeContext(browser: import("@playwright/test").Browser): Promise<BrowserContext> {
  return browser.newContext(
    process.env.PLAYWRIGHT_VIDEO === "on"
      ? { recordVideo: { dir: "test-results/videos", size: { width: 800, height: 600 } } }
      : {},
  );
}

// ADR 0001/0003: 2 ユーザーが同一 document を編集し、op が ActionCable(Solid Cable) で
// fan-out されて双方の canvas が同一状態に収束することを実機フルスタックで確認する。
test("op fan-out: 2 ユーザーの create/delete がリアルタイムに収束する", async ({ browser, playwright }) => {
  const api = await playwright.request.newContext();
  const ts = Date.now();
  const alice = await signup(api, `alice-${ts}@example.com`, "Alice");
  const bob = await signup(api, `bob-${ts}@example.com`, "Bob");

  const docRes = await api.post(`${BACKEND}/documents`, {
    headers: { Authorization: alice.token, "Content-Type": "application/json" },
    data: { name: `demo-${ts}` },
  });
  const docId = (await docRes.json()).id as number;
  await api.post(`${BACKEND}/documents/${docId}/members`, {
    headers: { Authorization: alice.token, "Content-Type": "application/json" },
    data: { user_id: bob.id, role: "editor" },
  });

  const actx = await makeContext(browser);
  const bctx = await makeContext(browser);
  const ap = await openDoc(actx, alice.token, docId);
  const bp = await openDoc(bctx, bob.token, docId);
  await beat(ap, 400);

  // 1. alice が矩形を追加 → bob にも fan-out (create op)
  await ap.getByTestId("add-rect").click();
  await expect(shapes(ap)).toHaveCount(1);
  await expect(shapes(bp)).toHaveCount(1, { timeout: 15_000 });
  await beat(ap);

  // 2. bob が楕円を追加 → alice にも fan-out (双方向)
  await bp.getByTestId("add-ellipse").click();
  await expect(shapes(bp)).toHaveCount(2);
  await expect(shapes(ap)).toHaveCount(2, { timeout: 15_000 });
  await beat(ap);

  // 3. bob が 1 つ選択して削除 → alice 側も 1 個に収束 (delete = "deleted" への LWW op)
  await shapes(bp).first().click();
  await bp.getByTestId("delete").click();
  await expect(shapes(bp)).toHaveCount(1);
  await expect(shapes(ap)).toHaveCount(1, { timeout: 15_000 });
  await beat(ap, 900);

  await actx.close();
  await bctx.close();
  await api.dispose();
});

// viewer は op を投入できない (ADR 0004) ことを確認する。
test("viewer は編集ボタンが無効 (op を投入できない)", async ({ browser, playwright }) => {
  const api = await playwright.request.newContext();
  const ts = Date.now();
  const owner = await signup(api, `owner-${ts}@example.com`, "Owner");
  const watcher = await signup(api, `watcher-${ts}@example.com`, "Watcher");

  const docRes = await api.post(`${BACKEND}/documents`, {
    headers: { Authorization: owner.token, "Content-Type": "application/json" },
    data: { name: `viewer-${ts}` },
  });
  const docId = (await docRes.json()).id as number;
  await api.post(`${BACKEND}/documents/${docId}/members`, {
    headers: { Authorization: owner.token, "Content-Type": "application/json" },
    data: { user_id: watcher.id, role: "viewer" },
  });

  const wctx = await makeContext(browser);
  const wp = await openDoc(wctx, watcher.token, docId);
  await expect(wp.getByTestId("role")).toHaveText("role: viewer");
  await expect(wp.getByTestId("add-rect")).toBeDisabled();

  await wctx.close();
  await api.dispose();
});
