import { test, expect } from "@playwright/test";
import { setViewerInBrowser } from "./helpers";

// outside_collaborator (carol) は private repo `acme/tools` に対して base 継承を持たない (ADR 0002)
test("outside_collaborator does not see the private repository in org listing", async ({ page }) => {
  await setViewerInBrowser(page, "carol");

  await page.goto("/");
  // organization 自体は表示される (公開情報)
  await expect(page.getByRole("heading", { name: /ACME/ })).toBeVisible();
  // 取得できる repositories は scope で絞られ、private な tools は出てこない
  const repoListItem = page.locator("li", { has: page.getByRole("link", { name: "acme/tools" }) });
  await expect(repoListItem).toHaveCount(0);
  await expect(page.getByText("visible なリポジトリがありません")).toBeVisible();
});
