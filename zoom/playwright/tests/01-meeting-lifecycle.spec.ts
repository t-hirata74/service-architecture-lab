import { test, expect } from "@playwright/test";
import { authenticateViaApi } from "./helpers";

// ADR 0001 + ADR 0003: 会議ライフサイクルのハッピーパス。
// scheduled → waiting_room → live → ended → recorded → summarized を E2E で確認。
test("meeting lifecycle: scheduled → live → ended → summarized (with summary body)", async ({ page }) => {
  await authenticateViaApi(page, { displayName: "Alice Host" });

  // 会議作成
  await page.goto("/meetings/new");
  await page.waitForLoadState("networkidle");
  await page.getByTestId("title-input").fill("E2E Lifecycle Demo");
  await page.getByTestId("submit-button").click();

  await expect(page).toHaveURL(/\/meetings\/\d+/);
  await expect(page.getByText("scheduled", { exact: true })).toBeVisible();

  // open
  await page.getByTestId("btn-open").click();
  await expect(page.getByText("waiting_room", { exact: true })).toBeVisible({ timeout: 10_000 });

  // start (go live)
  await page.getByTestId("btn-start").click();
  await expect(page.getByText("live", { exact: true })).toBeVisible({ timeout: 10_000 });

  // end
  await page.getByTestId("btn-end").click();

  // ended → recorded → summarized へ進む。Solid Queue が pickup するため少し時間がかかる。
  await expect(page.getByText("summarized", { exact: true })).toBeVisible({ timeout: 60_000 });

  // 要約 body が表示される
  await expect(page.getByText("[mock summary]")).toBeVisible({ timeout: 10_000 });
});
