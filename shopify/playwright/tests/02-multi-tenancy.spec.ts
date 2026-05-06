import { test, expect } from "@playwright/test";
import { captureCtxOpts } from "./helpers";

// ADR 0002 (`shop_id` row-level scoping) の可視化:
//   acme と globex に同 slug "t-shirt" が別 title で存在。
//   tenant switcher を切り替えると一覧と同 slug の表示 title が入れ替わる。

test("ADR 0002: tenant switcher で acme ↔ globex の products が入れ替わる", async ({ browser }, testInfo) => {
  const ctx = await browser.newContext(captureCtxOpts(testInfo));
  const page = await ctx.newPage();

  // 1) acme で開く (default)
  await page.goto("/");
  // dropdown の <option> も "ACME Apparel" にマッチするので heading で固定する
  await expect(page.getByRole("heading", { name: "ACME Apparel" })).toBeVisible();
  await expect(page.getByTestId("product-t-shirt")).toContainText("ACME Logo Tee");
  // ACME 限定の hoodie が見える
  await expect(page.getByTestId("product-limited-hoodie")).toBeVisible();
  await page.waitForTimeout(800);

  // 2) tenant switcher で globex に切替
  await page.getByTestId("shop-switcher").locator("select").selectOption("globex");
  await expect(page.getByRole("heading", { name: "Globex Goods" })).toBeVisible();
  // 同 slug t-shirt が globex の title で表示される (= 別行)
  await expect(page.getByTestId("product-t-shirt")).toContainText("Globex Engineer Tee");
  // globex には hoodie が存在しない
  await expect(page.getByTestId("product-limited-hoodie")).toHaveCount(0);
  // globex 固有 product
  await expect(page.getByTestId("product-notebook")).toBeVisible();
  await page.waitForTimeout(1_500);

  // 3) acme に戻して入れ替わりを再演出 (gif の往復が見えやすい)
  await page.getByTestId("shop-switcher").locator("select").selectOption("acme");
  await expect(page.getByTestId("product-t-shirt")).toContainText("ACME Logo Tee");
  await page.waitForTimeout(1_000);

  await ctx.close();
});
