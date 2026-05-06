import { test, expect } from "@playwright/test";
import { authenticateViaApi } from "./helpers";

// ADR 0002: 動的ホスト譲渡を E2E で確認 (2 BrowserContext)。
// alice (host) と bob (participant) を別 context で同じ会議に揃え、
// alice から bob に Transfer host → bob 側の UI が host 操作を出す。
test("dynamic host transfer: alice → bob during live", async ({ browser }) => {
  const aliceCtx = await browser.newContext();
  const bobCtx = await browser.newContext();
  const alice = await aliceCtx.newPage();
  const bob = await bobCtx.newPage();

  // alice: API auth + create meeting + open
  await authenticateViaApi(alice, { displayName: "Alice Host" });
  await alice.goto("/meetings/new");
  await alice.waitForLoadState("networkidle");
  await alice.getByTestId("title-input").fill("E2E Transfer Demo");
  await alice.getByTestId("submit-button").click();
  await expect(alice).toHaveURL(/\/meetings\/\d+/);
  const meetingId = alice.url().match(/\/meetings\/(\d+)/)![1];

  await alice.getByTestId("btn-open").click();
  await expect(alice.getByText("waiting_room", { exact: true })).toBeVisible({ timeout: 10_000 });

  // bob: auth + go to meeting + join
  const bobAuth = await authenticateViaApi(bob, { displayName: "Bob Joiner" });
  const bobUserId = JSON.parse(atob(bobAuth.token.split(".")[1])).account_id as number;

  await bob.goto(`/meetings/${meetingId}`);
  await bob.waitForLoadState("networkidle");
  await bob.getByTestId("btn-join").click();

  // alice: admit bob → live に自動遷移
  await expect(alice.getByText("Bob Joiner")).toBeVisible({ timeout: 10_000 });
  await alice.getByTestId(`btn-admit-${bobUserId}`).click();
  await expect(alice.getByText("live", { exact: true })).toBeVisible({ timeout: 10_000 });

  // alice: Transfer host to bob
  await alice.getByTestId(`btn-transfer-${bobUserId}`).click();

  // bob 側の UI が host 操作 (End meeting) を出す。alice 側からは消える。
  await expect(bob.getByTestId("btn-end")).toBeVisible({ timeout: 15_000 });
  await expect(alice.getByTestId("btn-end")).not.toBeVisible({ timeout: 15_000 });

  await aliceCtx.close();
  await bobCtx.close();
});
