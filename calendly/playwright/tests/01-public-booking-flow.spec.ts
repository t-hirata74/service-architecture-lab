import { test, expect, request } from "@playwright/test";
import { authenticateViaApi, apiCreateEventType, apiCreateAvailabilityRule, getHostIdFromEventType } from "./helpers";

// ADR 0001 happy path: host が event_type + availability を作成 → invitee 公開ページから slot 取得 → 予約 → 確認画面。
test("public booking flow: signup → setup → invitee picks a slot → booking confirmed", async ({ page }) => {
  const { token } = await authenticateViaApi(page);
  const ctx = await request.newContext();

  const eventTypeId = await apiCreateEventType(ctx, token, {
    slug: `consult-${Date.now().toString(36)}`,
    title: "30 min consult",
    duration_minutes: 30,
  });
  await apiCreateAvailabilityRule(ctx, token);
  const hostId = await getHostIdFromEventType(ctx, token, eventTypeId);

  // event_type の slug を再取得 (URL 用)
  const list = await (await ctx.get(`http://127.0.0.1:3100/event_types`, {
    headers: { "Content-Type": "application/json", Authorization: token },
  })).json();
  const slug = list.find((et: { id: number; slug: string }) => et.id === eventTypeId).slug;

  // 公開予約ページへ
  await page.goto(`/p/${hostId}/${slug}`);
  await expect(page.getByRole("heading", { name: /E2E Host/ })).toBeVisible({ timeout: 15_000 });

  // 最初に表示された slot を選択
  const firstSlot = page.getByTestId("slot-button").first();
  await expect(firstSlot).toBeVisible({ timeout: 15_000 });
  await firstSlot.click();

  // 確認フォーム
  await expect(page.getByTestId("invitee-form")).toBeVisible();
  await page.getByTestId("invitee-name").fill("Alice Invitee");
  await page.getByTestId("invitee-email").fill(`invitee-${Date.now()}@example.com`);
  await page.getByTestId("confirm-button").click();

  // 確定画面が出る (= 200 created を経由)
  await expect(page.getByTestId("confirmed-message")).toBeVisible({ timeout: 15_000 });
});
