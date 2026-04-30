import { test, expect } from "@playwright/test";
import { signupViaUI, uniqueEmail, uniqueChannelName } from "./helpers";

const PASSWORD = "correcthorsebatterystaple";
const API_URL = "http://localhost:3010";

test.describe("既読 cursor (ADR 0002)", () => {
  test("チャンネル閲覧で未読インジケータが消える (auto-mark-read)", async ({ browser }) => {
    // Bob: チャンネル作成と投稿で未読の元を仕込む
    const bobCtx = await browser.newContext();
    const bob = await bobCtx.newPage();
    const bobEmail = uniqueEmail("bob");
    await signupViaUI(bob, { displayName: "Bob", email: bobEmail, password: PASSWORD });

    const channelName = uniqueChannelName("rs");
    await bob.getByLabel("新規チャンネル").fill(channelName);
    await bob.getByRole("button", { name: "Create channel" }).click();
    await expect(bob).toHaveURL(/\/channels\/\d+/);
    const channelId = Number(bob.url().match(/\/channels\/(\d+)/)![1]);

    await bob.getByLabel("メッセージ").fill("Bob からの未読メッセージ");
    await bob.getByRole("button", { name: "送信" }).click();
    await expect(bob.getByText("Bob からの未読メッセージ")).toBeVisible();

    // Alice: signup → join → /channels に未読バッジが出る
    const aliceCtx = await browser.newContext();
    const alice = await aliceCtx.newPage();
    const aliceEmail = uniqueEmail("alice");
    await signupViaUI(alice, { displayName: "Alice", email: aliceEmail, password: PASSWORD });

    await alice.evaluate(
      async ({ id, apiUrl }) => {
        const token = localStorage.getItem("jwt");
        await fetch(`${apiUrl}/channels/${id}/join`, {
          method: "POST",
          headers: { Authorization: token! },
        });
      },
      { id: channelId, apiUrl: API_URL },
    );

    // join 後にサイドバーを再読込するため /channels に再アクセス
    await alice.goto("/channels");
    const channelLink = alice.locator(`a[data-channel-id="${channelId}"]`);
    await expect(channelLink).toHaveAttribute("data-unread", "true", { timeout: 5_000 });

    // チャンネルを開くと auto-mark-read が走る
    await channelLink.click();
    await expect(alice).toHaveURL(new RegExp(`/channels/${channelId}$`));
    await expect(alice.getByText("Bob からの未読メッセージ")).toBeVisible();

    // 同じタブでも UserChannel で read.advanced が届き、サイドバーが更新される
    await expect(channelLink).toHaveAttribute("data-unread", "false", { timeout: 5_000 });

    await aliceCtx.close();
    await bobCtx.close();
  });
});
