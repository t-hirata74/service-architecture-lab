import { test, expect } from "@playwright/test";
import path from "node:path";
import { uniqueTitle, SEED_USER_EMAIL } from "./helpers";

// アップロード → ポーリング → ready → publish → 一覧出現 まで通す。
// Solid Queue worker が起動していないと transcoding で止まる。
// (`bundle exec bin/jobs` が稼働している前提)
test("upload flow drives the state machine to published", async ({ page }) => {
  test.skip(!process.env.JOBS_RUNNING, "Solid Queue worker が必要 (JOBS_RUNNING=1 で有効化)");

  const title = uniqueTitle("E2E アップロード");
  const fixturePath = path.join(__dirname, "fixtures", "tiny.mp4");

  await page.goto("/upload");
  await page.getByLabel("投稿者メール").fill(SEED_USER_EMAIL);
  await page.getByLabel("タイトル").fill(title);
  await page.getByLabel("説明").fill("Phase 5 E2E");
  await page.getByLabel("動画ファイル").setInputFiles(fixturePath);
  await page.getByRole("button", { name: "アップロード" }).click();

  // /processing へ遷移
  await page.waitForURL(/\/videos\/\d+\/processing/);

  // status: ready になるまで最大 15 秒ポーリング
  const publishButton = page.getByRole("button", { name: /公開する/ });
  await expect(publishButton).toBeVisible({ timeout: 15_000 });
  await publishButton.click();

  await page.waitForURL(/\/videos\/\d+$/);
  await expect(page.getByRole("heading", { name: title })).toBeVisible();
});
