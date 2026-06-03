import {
  test,
  expect,
  type BrowserContext,
  type APIRequestContext,
  type TestInfo,
} from "@playwright/test";

/** PLAYWRIGHT_VIDEO=on で browser.newContext() に recordVideo を inject (capture 用)。 */
function captureCtxOpts(testInfo: TestInfo): { recordVideo?: { dir: string } } {
  return process.env.PLAYWRIGHT_VIDEO === "on"
    ? { recordVideo: { dir: testInfo.outputDir } }
    : {};
}

// uber dispatch の headline フローを 2 BrowserContext で観測する。
//   - driver context: WebSocket で go online → offer を受けて accept
//   - rider context : REST POST /trips → GET /trips/:id を poll → driver_accepted
// backend は rider=REST poll / driver=WS と非対称 (internal/ws/protocol.go)。
// その非対称な 2 経路が 1 つの trip で出会う様子を side-by-side で見せる。

const BACKEND_URL = "http://localhost:3110";

type Auth = { token: string; user: { id: number; role: string; display_name: string } };

// API で fresh user を作る (email は run ごとに一意)。
async function registerUser(
  api: APIRequestContext,
  role: "rider" | "driver",
  tag: string,
): Promise<Auth> {
  const email = `${role}-${tag}@example.com`;
  const res = await api.post(`${BACKEND_URL}/auth/register`, {
    data: { email, password: "password123", role, display_name: `${role}-${tag}` },
  });
  expect(res.ok(), `register ${role} failed: ${res.status()}`).toBeTruthy();
  return (await res.json()) as Auth;
}

// localStorage に token/user を仕込んでから対象ページへ遷移する。
async function seedAuthAndGoto(ctx: BrowserContext, auth: Auth, path: string) {
  await ctx.addInitScript(
    ([t, u]) => {
      localStorage.setItem("uber-token", t as string);
      localStorage.setItem("uber-user", u as string);
    },
    [auth.token, JSON.stringify(auth.user)],
  );
  const page = await ctx.newPage();
  await page.goto(path);
  return page;
}

test("ride dispatch :: rider request → driver offer → accept → driver_accepted", async ({
  browser,
  request,
}, testInfo) => {
  const tag = `${Date.now()}`;
  const driverAuth = await registerUser(request, "driver", tag);
  const riderAuth = await registerUser(request, "rider", tag);

  // driver(WS) | rider(REST) を hstack するため、driver を先に (左ペイン) 作る
  const driverCtx = await browser.newContext(captureCtxOpts(testInfo));
  const riderCtx = await browser.newContext(captureCtxOpts(testInfo));

  // 1. driver: 渋谷で go online → WS open → status online
  const driverPage = await seedAuthAndGoto(driverCtx, driverAuth, "/driver");
  await driverPage.getByRole("button", { name: "Go online" }).click();
  await expect(driverPage.getByTestId("driver-status")).toHaveAttribute(
    "data-status",
    "online",
  );

  // 2. rider: pickup=渋谷(default) dropoff=新宿(default) で配車要求
  const riderPage = await seedAuthAndGoto(riderCtx, riderAuth, "/rider");
  await riderPage.getByRole("button", { name: "Request ride" }).click();

  // 3. driver: 同一 H3 cell の matcher から offer が届く
  await expect(driverPage.getByTestId("offer-card")).toBeVisible({ timeout: 15_000 });
  await driverPage.getByTestId("accept-btn").click();

  // 4. driver: 楽観的に matched 表示
  await expect(driverPage.getByTestId("driver-status")).toHaveAttribute(
    "data-status",
    "matched",
  );

  // 5. rider: poll が driver_accepted を観測し、担当 driver id が出る
  await expect(riderPage.getByTestId("trip-status")).toHaveAttribute(
    "data-status",
    "driver_accepted",
    { timeout: 15_000 },
  );
  await expect(riderPage.getByTestId("driver-id")).toBeVisible();

  await driverCtx.close();
  await riderCtx.close();
});

test("rider cancel :: matching 中にドライバ不在で cancel → canceled", async ({
  browser,
  request,
}, testInfo) => {
  const tag = `${Date.now()}`;
  // driver を online にしない都市 (東京駅) を pickup にして no-driver の matching を作る
  const riderAuth = await registerUser(request, "rider", `cancel-${tag}`);

  const riderCtx = await browser.newContext(captureCtxOpts(testInfo));
  const riderPage = await seedAuthAndGoto(riderCtx, riderAuth, "/rider");

  // pickup=東京駅 / dropoff=品川駅 を選択 (この cell には driver がいない)
  await riderPage.getByLabel("pickup").selectOption("tokyo");
  await riderPage.getByLabel("dropoff").selectOption("shinagawa");
  await riderPage.getByRole("button", { name: "Request ride" }).click();

  // matching のまま (driver がいないので driver_accepted に進まない)
  await expect(riderPage.getByTestId("trip-status")).toHaveAttribute(
    "data-status",
    "matching",
    { timeout: 15_000 },
  );

  // rider が cancel → canceled に遷移
  await riderPage.getByRole("button", { name: "cancel" }).click();
  await expect(riderPage.getByTestId("trip-status")).toHaveAttribute(
    "data-status",
    "canceled",
    { timeout: 15_000 },
  );

  await riderCtx.close();
});
