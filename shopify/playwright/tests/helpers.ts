import { type BrowserContext, type Page, type TestInfo, expect } from "@playwright/test";

/** PLAYWRIGHT_VIDEO=on のとき browser.newContext() に recordVideo を inject (capture 用) */
export function captureCtxOpts(testInfo: TestInfo): { recordVideo?: { dir: string } } {
  return process.env.PLAYWRIGHT_VIDEO === "on"
    ? { recordVideo: { dir: testInfo.outputDir } }
    : {};
}

/** localStorage に tenant 選択を入れる (Header の useShop 初期値になる) */
export async function setShopBeforeLoad(ctx: BrowserContext, subdomain: string) {
  await ctx.addInitScript((sub) => {
    window.localStorage.setItem("shopify_lab.shop", sub);
  }, subdomain);
}

/** /login に遷移して register → 自動的に / に戻ってくる */
export async function registerOnUI(page: Page, email: string, password = "passw0rd") {
  await page.goto("/login");
  await page.getByTestId("email-input").fill(email);
  await page.getByTestId("password-input").fill(password);
  await page.getByTestId("submit-button").click();
  await expect(page.getByTestId("auth-email")).toHaveText(`@${email}`, { timeout: 15_000 });
}
