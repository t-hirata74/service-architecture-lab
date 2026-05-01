import { test, expect } from "@playwright/test";
import { setViewerInBrowser, SEED } from "./helpers";

test("organization → repository → PR detail navigation", async ({ page }) => {
  await setViewerInBrowser(page, "alice");

  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Organization" })).toBeVisible();

  // repository link が出ていること (seed: acme/tools)
  const repoLink = page.getByRole("link", { name: `${SEED.org}/${SEED.repo}` });
  await expect(repoLink).toBeVisible();
  await repoLink.click();

  await expect(page).toHaveURL(new RegExp(`/${SEED.org}/${SEED.repo}$`));
  await expect(page.getByRole("heading", { name: /tools/ })).toBeVisible();

  // Issues / Pull requests 両セクションが見える
  await expect(page.getByText(/Issues \(\d+\)/)).toBeVisible();
  await expect(page.getByText(/Pull requests \(\d+\)/)).toBeVisible();

  // seed PR (#2) → 詳細画面
  await page.getByRole("link", { name: `#${SEED.prNumber}` }).click();
  await expect(page).toHaveURL(new RegExp(`/${SEED.org}/${SEED.repo}/pull/${SEED.prNumber}$`));
  await expect(page.getByRole("heading", { name: /Seed PR/ })).toBeVisible();
});
