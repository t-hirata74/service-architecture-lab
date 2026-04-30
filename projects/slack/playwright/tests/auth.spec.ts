import { test, expect } from "@playwright/test";
import { signupViaUI, loginViaUI, uniqueEmail } from "./helpers";

const PASSWORD = "correcthorsebatterystaple";

test.describe("認証フロー", () => {
  test("signup -> /channels に到達し、サイドバーに表示名が出る", async ({ page }) => {
    const email = uniqueEmail("signup");
    await signupViaUI(page, { displayName: "Alice E2E", email, password: PASSWORD });

    await expect(page.getByText("Alice E2E")).toBeVisible();
    await expect(page.getByText("Channels")).toBeVisible();
  });

  test("signup -> logout -> login で同じユーザーに戻れる", async ({ page }) => {
    const email = uniqueEmail("relogin");
    await signupViaUI(page, { displayName: "Bob E2E", email, password: PASSWORD });

    await page.getByRole("button", { name: "ログアウト" }).click();
    await expect(page).toHaveURL(/\/login$/);

    await loginViaUI(page, { email, password: PASSWORD });
    await expect(page.getByText("Bob E2E")).toBeVisible();
  });

  test("未認証で /channels にアクセスすると /login に飛ばされる", async ({ page }) => {
    await page.context().clearCookies();
    await page.goto("/channels");
    await expect(page).toHaveURL(/\/login$/);
  });
});
