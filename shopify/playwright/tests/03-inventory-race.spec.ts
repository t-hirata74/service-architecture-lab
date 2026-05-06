import { test, expect, type Page } from "@playwright/test";
import { captureCtxOpts, registerOnUI, setShopBeforeLoad } from "./helpers";

// ADR 0003 (条件付き UPDATE で在庫を atomic 減算) の可視化:
//   on_hand=1 の "limited-hoodie" を 2 人 (alice / bob) が同時に checkout。
//   片方は order #1 確定、片方は "在庫不足" 表示 → 並行制御が DB 層で効いていることを見せる。

async function addLimitedHoodieToCart(page: Page) {
  await page.goto("/products/limited-hoodie");
  await expect(page.getByTestId("product-title")).toHaveText("ACME Limited Hoodie");
  await page.getByTestId("add-ACM-HOOD-LMT").click();
  await expect(page.getByTestId("flash")).toHaveText("added to cart");
  await page.goto("/cart");
  await expect(page.getByTestId("cart-items")).toContainText("ACM-HOOD-LMT");
}

test("ADR 0003: 同時 checkout の片方だけが成功し、もう片方は在庫不足になる", async ({ browser }, testInfo) => {
  const ts = Date.now();
  const aliceCtx = await browser.newContext(captureCtxOpts(testInfo));
  const bobCtx = await browser.newContext(captureCtxOpts(testInfo));
  await setShopBeforeLoad(aliceCtx, "acme");
  await setShopBeforeLoad(bobCtx, "acme");

  const a = await aliceCtx.newPage();
  const b = await bobCtx.newPage();

  // 並行で register & cart 準備 (時間短縮)
  await Promise.all([
    registerOnUI(a, `alice_${ts}@example.com`),
    registerOnUI(b, `bob_${ts}@example.com`),
  ]);
  await Promise.all([addLimitedHoodieToCart(a), addLimitedHoodieToCart(b)]);

  // 「同時押し」を演出: 直前で少し溜めてから 2 つを同時に click
  await a.bringToFront();
  await a.waitForTimeout(500);

  // checkout を **並行起動**。Promise.all で両方の click を同時に発火させる。
  await Promise.all([
    a.getByTestId("checkout-button").click(),
    b.getByTestId("checkout-button").click(),
  ]);

  // どちらか一方だけが order を確定し、もう一方は error を出す
  const aHasOrder  = a.getByTestId("order-confirmation");
  const aHasError  = a.getByTestId("checkout-error");
  const bHasOrder  = b.getByTestId("order-confirmation");
  const bHasError  = b.getByTestId("checkout-error");

  // 両ページの結果が出るまで待つ (Promise.race ではなく両方表示を待つ)
  await Promise.all([
    Promise.race([aHasOrder.waitFor({ timeout: 15_000 }), aHasError.waitFor({ timeout: 15_000 })]),
    Promise.race([bHasOrder.waitFor({ timeout: 15_000 }), bHasError.waitFor({ timeout: 15_000 })]),
  ]);

  const aWon = await aHasOrder.isVisible();
  const bWon = await bHasOrder.isVisible();

  // ちょうど 1 人が成功
  expect([aWon, bWon].filter(Boolean).length).toBe(1);

  if (aWon) {
    await expect(aHasOrder).toContainText("order #1 created");
    await expect(bHasError).toContainText(/在庫不足|insufficient_stock/);
  } else {
    await expect(bHasOrder).toContainText("order #1 created");
    await expect(aHasError).toContainText(/在庫不足|insufficient_stock/);
  }

  // gif の最後で結果が読める時間を確保
  await a.waitForTimeout(1_500);
  await b.waitForTimeout(1_500);

  await aliceCtx.close();
  await bobCtx.close();
});
