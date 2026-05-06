import { test, expect } from "@playwright/test";
import { captureCtxOpts } from "./helpers";

// ADR 0001 (modular monolith / Engine + packwerk) の可視化:
//   /admin/system に 5 Engine + 依存方向 + packwerk pass バッジが出ていることを確認。
//   gif としては、トップから system へ navigate → Engine 群と forbidden 一覧を見せる。

test("ADR 0001: /admin/system が 5 Engine + 依存方向 + packwerk pass を表示する", async ({ browser }, testInfo) => {
  const ctx = await browser.newContext(captureCtxOpts(testInfo));
  const page = await ctx.newPage();

  await page.goto("/");
  // header の system リンクから遷移する (gif で「ナビ → 該当ページ」の流れを撮る)
  await page.getByRole("link", { name: "system" }).click();
  await expect(page.getByTestId("system-page")).toBeVisible();

  // 5 Engine がカードとして並んでいる
  for (const id of ["core", "catalog", "inventory", "orders", "apps"]) {
    await expect(page.getByTestId(`engine-${id}`)).toBeVisible();
  }

  // packwerk pass バッジ + forbidden / allowed の節
  await expect(page.getByText(/packwerk: 0 violations/)).toBeVisible();
  await expect(page.getByText(/allowed dependencies/)).toBeVisible();
  await expect(page.getByText(/forbidden \(CI fails\)/)).toBeVisible();

  // gif の最後に画面の主要ブロックが映るよう、forbidden 節までスクロールしてから少し止める
  await page.getByText(/forbidden \(CI fails\)/).scrollIntoViewIfNeeded();
  await page.waitForTimeout(2_000);

  await ctx.close();
});
