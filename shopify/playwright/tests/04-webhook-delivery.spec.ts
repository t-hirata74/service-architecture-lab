import { test, expect } from "@playwright/test";
import { captureCtxOpts, registerOnUI, setShopBeforeLoad } from "./helpers";

// ADR 0004 (Webhook delivery: Solid Queue + HMAC + delivery_id idempotency) の可視化:
//   storefront で checkout 成功 → 同時に mock receiver (:4321) UI に webhook が表示される。
//   左ペインが store / 右ペインが mock receiver になる構成 (capture 時に hstack)。

test("ADR 0004: checkout が webhook として mock receiver に HMAC verified で配信される", async ({ browser }, testInfo) => {
  const ts = Date.now();

  const storeCtx = await browser.newContext(captureCtxOpts(testInfo));
  const recvCtx = await browser.newContext(captureCtxOpts(testInfo));
  await setShopBeforeLoad(storeCtx, "acme");

  const store = await storeCtx.newPage();
  const recv = await recvCtx.newPage();

  // mock receiver UI を先に開いて履歴をリセット (前 spec の delivery が残らない)
  await recv.goto("http://localhost:4321/");
  await recv.evaluate(() => fetch("/api/reset", { method: "POST" }));
  await expect(recv.getByText("no webhooks received yet")).toBeVisible();

  // store: register → mug をカートへ → checkout
  await registerOnUI(store, `webhook_buyer_${ts}@example.com`);
  await store.goto("/products/mug");
  await store.getByTestId("add-ACM-MUG-001").click();
  await expect(store.getByTestId("flash")).toHaveText("added to cart");

  await store.goto("/cart");
  await store.getByTestId("checkout-button").click();
  await expect(store.getByTestId("order-confirmation")).toContainText(/order #\d+ created/);

  // mock receiver UI に webhook が出るのを待つ (Solid Queue の dispatch 待ち)
  await expect(recv.getByText("order_created")).toBeVisible({ timeout: 30_000 });
  await expect(recv.getByText("HMAC verified")).toBeVisible();
  await expect(recv.getByText(/delivery_id:\s+[0-9a-f-]{36}/)).toBeVisible();

  // gif の最後で payload が映える時間を確保
  await recv.waitForTimeout(2_000);

  await storeCtx.close();
  await recvCtx.close();
});
