import { test, expect } from "@playwright/test";

// 一覧 → 詳細 → コメントセクション表示まで。seeds の動画があることを前提。
test("home page lists videos and detail page renders", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Trending" })).toBeVisible();

  // seed: "Rails 8 + Solid Queue 入門" が含まれる
  const card = page.getByRole("link", { name: /Rails 8 \+ Solid Queue 入門/ });
  await expect(card).toBeVisible();

  await card.click();
  await expect(page.getByRole("heading", { name: /Rails 8 \+ Solid Queue 入門/ })).toBeVisible();

  // 関連動画セクションとコメント欄が表示される
  await expect(page.getByRole("heading", { name: "関連動画" })).toBeVisible();
  await expect(page.getByText(/コメント \(\d+\)/)).toBeVisible();
});
