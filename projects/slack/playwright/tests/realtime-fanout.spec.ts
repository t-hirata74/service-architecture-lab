import { test, expect } from "@playwright/test";
import { signupViaUI, uniqueEmail, uniqueChannelName } from "./helpers";

const PASSWORD = "correcthorsebatterystaple";
const API_URL = "http://localhost:3000";

test.describe("リアルタイム fan-out (ADR 0001)", () => {
  test("Alice 送信 -> Bob が受信 / Bob 送信 -> Alice が受信", async ({ browser }) => {
    // 別 BrowserContext を 2 つ立ち上げて 2 ユーザーをシミュレート
    const aliceCtx = await browser.newContext();
    const bobCtx = await browser.newContext();
    const alice = await aliceCtx.newPage();
    const bob = await bobCtx.newPage();

    const aliceEmail = uniqueEmail("alice");
    const bobEmail = uniqueEmail("bob");

    await signupViaUI(alice, { displayName: "Alice", email: aliceEmail, password: PASSWORD });
    await signupViaUI(bob, { displayName: "Bob", email: bobEmail, password: PASSWORD });

    // Alice がチャンネル作成
    const channelName = uniqueChannelName("rt");
    await alice.getByLabel("新規チャンネル").fill(channelName);
    await alice.getByRole("button", { name: "Create channel" }).click();
    await expect(alice).toHaveURL(/\/channels\/\d+/);

    const channelId = Number(alice.url().match(/\/channels\/(\d+)/)![1]);

    // Bob は API で join (UI からの招待フローはまだ未実装)
    const joinStatus = await bob.evaluate(
      async ({ id, apiUrl }) => {
        const token = localStorage.getItem("jwt");
        const res = await fetch(`${apiUrl}/channels/${id}/join`, {
          method: "POST",
          headers: { Authorization: token! },
        });
        return res.status;
      },
      { id: channelId, apiUrl: API_URL },
    );
    expect(joinStatus).toBe(200);

    // Bob がチャンネルに移動して購読を確立
    await bob.goto(`/channels/${channelId}`);
    await expect(bob.getByText(`# ${channelName}`)).toBeVisible();
    // 購読が WebSocket で確立する短い時間を待つ
    await bob.waitForTimeout(300);

    // Alice -> Bob
    await alice.getByLabel("メッセージ").fill("Hello Bob");
    await alice.getByRole("button", { name: "送信" }).click();
    await expect(bob.getByText("Hello Bob")).toBeVisible({ timeout: 5_000 });

    // Bob -> Alice
    await bob.getByLabel("メッセージ").fill("Hi Alice");
    await bob.getByRole("button", { name: "送信" }).click();
    await expect(alice.getByText("Hi Alice")).toBeVisible({ timeout: 5_000 });

    await aliceCtx.close();
    await bobCtx.close();
  });
});
