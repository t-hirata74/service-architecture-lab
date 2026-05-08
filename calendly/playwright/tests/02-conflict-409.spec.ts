import { test, expect, request } from "@playwright/test";
import { authenticateViaApi, apiCreateEventType, apiCreateAvailabilityRule, apiCreateBooking } from "./helpers";

// ADR 0002 fixate (HTTP 層): 同じスロットに 2 つ目の予約 → 409 booking_conflict。
test("booking conflict returns 409 when two invitees pick the same slot", async ({ page }) => {
  const { token } = await authenticateViaApi(page);
  const ctx = await request.newContext();

  const eventTypeId = await apiCreateEventType(ctx, token, {
    slug: `conflict-${Date.now().toString(36)}`,
    title: "Conflict Test",
    duration_minutes: 60,
  });
  await apiCreateAvailabilityRule(ctx, token);

  // 2026-06-01 (Mon) 09:00 JST = 2026-06-01 00:00 UTC を狙う (rule に含まれる時間帯)
  const start = "2026-06-01T00:00:00Z";

  const r1 = await apiCreateBooking(ctx, {
    event_type_id: eventTypeId,
    start_at: start,
    invitee_email: `first-${Date.now()}@example.com`,
  });
  expect(r1.status()).toBe(201);

  const r2 = await apiCreateBooking(ctx, {
    event_type_id: eventTypeId,
    start_at: start,
    invitee_email: `second-${Date.now()}@example.com`,
  });
  expect(r2.status()).toBe(409);
  const body = await r2.json();
  expect(body.error).toBe("booking_conflict");
});
