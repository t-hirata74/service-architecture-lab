import { test, expect, type Page } from "@playwright/test";

// E2E: register → post → timeline で自分の post が見える
// ADR 0001: self entry は signal で同期 INSERT されるので Celery 待ちなし

async function register(page: Page, username: string, password: string) {
  await page.goto("/register");
  await page.getByLabel("username").fill(username);
  await page.getByLabel(/password/).fill(password);
  await page.getByRole("button", { name: /create account/ }).click();
  await expect(page).toHaveURL("/", { timeout: 10_000 });
}

test("register → post 投稿 → 自分の timeline に出る", async ({ page }) => {
  const username = `e2e_${Date.now()}`;
  await register(page, username, "password123!");

  // 初期 timeline は空
  await expect(page.getByText(/タイムラインは空です/)).toBeVisible();

  // 投稿フォームへ移動して post
  await page.getByRole("link", { name: /^post$/ }).click();
  await expect(page).toHaveURL("/post/new");
  await page.getByLabel("image_url").fill("https://example.test/x.jpg");
  await page.getByLabel("caption").fill(`hello from ${username}`);
  await page.getByRole("button", { name: /^post$/ }).click();

  // timeline に投稿が出る (self entry 同期 INSERT)
  await expect(page).toHaveURL("/");
  await expect(page.getByText(`hello from ${username}`)).toBeVisible({
    timeout: 10_000,
  });
});

test("alice が bob を follow すると bob の post が alice の timeline に出る (fan-out)", async ({
  browser,
}) => {
  const ts = Date.now();
  const aliceName = `alice_${ts}`;
  const bobName = `bob_${ts}`;

  const aliceCtx = await browser.newContext();
  const bobCtx = await browser.newContext();
  const alicePage = await aliceCtx.newPage();
  const bobPage = await bobCtx.newPage();

  await register(alicePage, aliceName, "password123!");
  await register(bobPage, bobName, "password123!");

  // bob が投稿する (この時点では誰もフォローしていないので fan-out 先は self のみ)
  await bobPage.getByRole("link", { name: /^post$/ }).click();
  await bobPage
    .getByLabel("caption")
    .fill(`bob's post ${ts}`);
  await bobPage.getByRole("button", { name: /^post$/ }).click();
  await expect(bobPage).toHaveURL("/");

  // alice が bob を follow → backfill task が同期実行され、bob の直近 post が
  // alice の timeline に挿入される (CELERY_TASK_ALWAYS_EAGER=True)
  await alicePage.goto(`/users/${bobName}`);
  await alicePage.getByRole("button", { name: /^follow$/ }).click();
  await expect(
    alicePage.getByRole("button", { name: /^following$/ }),
  ).toBeVisible({ timeout: 5_000 });

  // alice の timeline に bob の post が現れる
  await alicePage.goto("/");
  await expect(alicePage.getByText(`bob's post ${ts}`)).toBeVisible({
    timeout: 10_000,
  });

  await aliceCtx.close();
  await bobCtx.close();
});

test("post の like ボタンで count が増える / 戻すと減る", async ({ page }) => {
  const username = `like_${Date.now()}`;
  await register(page, username, "password123!");

  // 投稿
  await page.goto("/post/new");
  await page.getByLabel("caption").fill("likeable");
  await page.getByRole("button", { name: /^post$/ }).click();
  await expect(page).toHaveURL("/");

  // ハート ♡ + 0 を確認 → クリックで ♥ + 1 に
  const heart = page.getByRole("button", { name: /[♡♥] \d+/ });
  await expect(heart).toContainText("0");
  await heart.click();
  await expect(heart).toContainText("1", { timeout: 5_000 });

  // もう一度押すと unlike で 0 に戻る
  await heart.click();
  await expect(heart).toContainText("0", { timeout: 5_000 });
});
