import { test, expect, type Page, type BrowserContext, type TestInfo } from "@playwright/test";

/** PLAYWRIGHT_VIDEO=on で browser.newContext() に recordVideo を inject (capture 用)。 */
function captureCtxOpts(testInfo: TestInfo): { recordVideo?: { dir: string } } {
  return process.env.PLAYWRIGHT_VIDEO === "on"
    ? { recordVideo: { dir: testInfo.outputDir } }
    : {};
}

// E2E focus: ADR 0001 / 0002 / 0003 が守られていること:
//   - alice の POST が WebSocket 経由で bob に届く (per-guild Hub fan-out)
//   - 双方向で MESSAGE_CREATE が伝播する
//   - presence (online) が相手側に表示される
//
// 1 ファイル 1 test、context を 2 つ並行起動して fan-out を観測する。

async function register(page: Page, username: string, password: string) {
  await page.goto("/login");
  // mode toggle button (outside the form)
  await page.locator('button:not([type="submit"])', { hasText: "register" }).click();
  await page.getByLabel("username").fill(username);
  await page.getByLabel("password").fill(password);
  // submit button (inside the form)
  await page.locator('button[type="submit"]').click();
  await expect(page).toHaveURL("/", { timeout: 15_000 });
}

async function login(page: Page, username: string, password: string) {
  await page.goto("/login");
  await page.locator('button:not([type="submit"])', { hasText: "login" }).click();
  await page.getByLabel("username").fill(username);
  await page.getByLabel("password").fill(password);
  await page.locator('button[type="submit"]').click();
  await expect(page).toHaveURL("/", { timeout: 15_000 });
}

async function createGuild(page: Page, name: string): Promise<number> {
  await page.getByPlaceholder("guild name").fill(name);
  await page.getByRole("button", { name: "create" }).click();
  // The created guild appears in the list with #id prefix.
  const idLocator = page.locator("li", { hasText: name }).locator("span").first();
  await expect(idLocator).toBeVisible({ timeout: 10_000 });
  const idText = (await idLocator.innerText()).replace("#", "");
  return Number(idText);
}

async function joinGuild(page: Page, guildId: number) {
  await page.getByPlaceholder("123").fill(String(guildId));
  await page.getByRole("button", { name: "join" }).click();
  await expect(page.locator("li", { hasText: `#${guildId}` })).toBeVisible({
    timeout: 10_000,
  });
}

async function openGuild(page: Page, guildId: number) {
  await page.goto(`/guilds/${guildId}`);
  // Wait for WS to reach the "open" state — green dot label "open".
  await expect(page.getByText(/^open$/)).toBeVisible({ timeout: 15_000 });
}

async function createChannel(page: Page, name: string) {
  await page.getByPlaceholder("new channel").fill(name);
  await page.getByRole("button", { name: "+ create" }).click();
  // Channel button becomes visible in the sidebar.
  await expect(
    page.getByRole("button", { name: new RegExp(`#\\s*${name}`) }),
  ).toBeVisible({ timeout: 10_000 });
}

async function send(page: Page, body: string) {
  await page.getByPlaceholder("message…").fill(body);
  await page.getByRole("button", { name: "send" }).click();
}

test("WebSocket fan-out: alice の発言が bob のページに即時反映される", async ({
  browser,
}, testInfo) => {
  test.setTimeout(120_000);
  const ts = Date.now();
  const alice = `alice_${ts}`;
  const bob = `bob_${ts}`;
  const password = "password123!";

  const aliceCtx: BrowserContext = await browser.newContext(captureCtxOpts(testInfo));
  const bobCtx: BrowserContext = await browser.newContext(captureCtxOpts(testInfo));
  const a = await aliceCtx.newPage();
  const b = await bobCtx.newPage();

  await register(a, alice, password);
  await register(b, bob, password);

  // alice creates a guild and a channel.
  const guildName = `g_${ts}`;
  const guildId = await createGuild(a, guildName);
  await openGuild(a, guildId);
  await createChannel(a, "general");

  // bob joins and opens the guild.
  await b.goto("/");
  await joinGuild(b, guildId);
  await openGuild(b, guildId);

  // Both should see "general" in the sidebar.
  await expect(a.getByRole("button", { name: /general/ })).toBeVisible();
  await expect(b.getByRole("button", { name: /general/ })).toBeVisible();

  // Each presence pane should show the *other* user as online.
  await expect(a.locator("aside", { hasText: "online" })).toContainText(
    `@${bob}`,
    { timeout: 15_000 },
  );
  await expect(b.locator("aside", { hasText: "online" })).toContainText(
    `@${alice}`,
    { timeout: 15_000 },
  );

  // alice sends a message — bob must see it via WebSocket fan-out (no reload).
  const msgFromAlice = `hello-from-alice-${ts}`;
  await send(a, msgFromAlice);
  await expect(b.getByText(msgFromAlice)).toBeVisible({ timeout: 10_000 });

  // bidirectional: bob replies, alice sees it without reload.
  const msgFromBob = `hello-from-bob-${ts}`;
  await send(b, msgFromBob);
  await expect(a.getByText(msgFromBob)).toBeVisible({ timeout: 10_000 });

  await aliceCtx.close();
  await bobCtx.close();
});

test("presence offline: 片方のタブを閉じると相手側の online list から消える", async ({
  browser,
}, testInfo) => {
  test.setTimeout(120_000);
  const ts = Date.now();
  const alice = `a2_${ts}`;
  const bob = `b2_${ts}`;
  const password = "password123!";

  const aliceCtx = await browser.newContext(captureCtxOpts(testInfo));
  const bobCtx = await browser.newContext(captureCtxOpts(testInfo));
  const a = await aliceCtx.newPage();
  const b = await bobCtx.newPage();

  await register(a, alice, password);
  await register(b, bob, password);

  const guildId = await createGuild(a, `gg_${ts}`);
  await openGuild(a, guildId);
  await createChannel(a, "general");

  await b.goto("/");
  await joinGuild(b, guildId);
  await openGuild(b, guildId);

  await expect(a.locator("aside", { hasText: "online" })).toContainText(
    `@${bob}`,
    { timeout: 15_000 },
  );

  // Close bob's context — server detects close, broadcasts PRESENCE_UPDATE(offline).
  await bobCtx.close();

  // alice's presence pane should drop bob within a few seconds.
  // ADR 0003: heartbeat ticker may take up to interval/2 to notice if close
  // frame is suppressed; here we close cleanly so it should be ~immediate.
  await expect(a.locator("aside", { hasText: "online" })).not.toContainText(
    `@${bob}`,
    { timeout: 15_000 },
  );

  await aliceCtx.close();
});
