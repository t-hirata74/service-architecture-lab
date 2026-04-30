import { test, expect } from "@playwright/test";
import { signupViaUI, uniqueEmail, uniqueChannelName } from "./helpers";

const PASSWORD = "correcthorsebatterystaple";

test.describe("AI 要約 (ai-worker)", () => {
  test("チャンネル要約ボタンで ai-worker からの要約が表示される", async ({ browser }) => {
    test.skip(
      !process.env.AI_WORKER_RUNNING,
      "ai-worker (localhost:8000) を別途立ち上げてから AI_WORKER_RUNNING=1 で実行",
    );

    const ctx = await browser.newContext();
    const page = await ctx.newPage();

    await signupViaUI(page, {
      displayName: "Alice",
      email: uniqueEmail("alice"),
      password: PASSWORD,
    });

    const channelName = uniqueChannelName("sum");
    await page.getByLabel("新規チャンネル").fill(channelName);
    await page.getByRole("button", { name: "Create channel" }).click();
    await expect(page).toHaveURL(/\/channels\/\d+/);

    // 数件の投稿
    for (const text of ["こんにちは", "新機能のレビューお願いします", "確認します！"]) {
      await page.getByLabel("メッセージ").fill(text);
      await page.getByRole("button", { name: "送信" }).click();
      await expect(page.getByText(text)).toBeVisible();
    }

    // 要約ボタンを押す
    await page.getByTestId("summarize-button").click();
    const panel = page.getByTestId("summary-panel");
    await expect(panel).toBeVisible({ timeout: 10_000 });
    await expect(panel).toContainText(channelName);
    await expect(panel).toContainText("3 件");

    await ctx.close();
  });
});
