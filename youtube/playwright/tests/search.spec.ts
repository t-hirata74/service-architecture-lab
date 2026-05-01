import { test, expect } from "@playwright/test";

// FULLTEXT (ngram) で日本語タイトルが拾えること。
test("search page returns results from MySQL ngram FULLTEXT", async ({ page }) => {
  await page.goto("/");
  await page.getByPlaceholder(/動画を検索/).fill("レコメンダ");
  await page.getByRole("button", { name: "検索" }).click();

  await expect(page).toHaveURL(/\/search\?q=/);
  await expect(page.getByRole("heading", { level: 1 })).toContainText("レコメンダ");
  await expect(page.getByRole("link", { name: /Python で簡易レコメンダ実装/ })).toBeVisible();
});

test("search page is empty for non-matching keyword", async ({ page }) => {
  // ngram parser でも絶対に当たらない一意な英数語
  await page.goto("/search?q=xyzqwertyabc12345unmatchable");
  await expect(page.getByText(/一致する動画はありませんでした/)).toBeVisible();
});
