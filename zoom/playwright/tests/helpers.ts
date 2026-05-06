import { type BrowserContext, type Page, request, expect } from "@playwright/test";

const BACKEND = "http://127.0.0.1:3090";

let counter = 0;
function uniqueEmail(prefix: string): string {
  counter += 1;
  return `${prefix}-${Date.now()}-${counter}@example.test`;
}

/**
 * Rails API を直接叩いて signup + login し、得た JWT を localStorage に書き込む。
 * UI の hydration race を避けるための helper。
 *
 * UI flow を見せたい場合 (capture 用 gif) は signupAndLoginViaUI を使う。
 */
export async function authenticateViaApi(
  page: Page,
  options: { displayName: string; email?: string; password?: string }
): Promise<{ email: string; displayName: string; token: string }> {
  const email = options.email ?? uniqueEmail(options.displayName.toLowerCase().replace(/\s+/g, ""));
  const password = options.password ?? "password123";

  const ctx = await request.newContext();
  const signupRes = await ctx.post(`${BACKEND}/create-account`, {
    data: { email, password, display_name: options.displayName },
    headers: { "Content-Type": "application/json", Accept: "application/json" },
  });
  if (![200, 201].includes(signupRes.status())) {
    throw new Error(`signup failed: ${signupRes.status()} ${await signupRes.text()}`);
  }

  const loginRes = await ctx.post(`${BACKEND}/login`, {
    data: { email, password },
    headers: { "Content-Type": "application/json", Accept: "application/json" },
  });
  if (loginRes.status() !== 200) {
    throw new Error(`login failed: ${loginRes.status()}`);
  }
  const token = loginRes.headers()["authorization"];
  if (!token) throw new Error("no Authorization header");
  await ctx.dispose();

  // localStorage に JWT を書く init script を仕込んで page を / に遷移させる。
  await page.addInitScript((t: string) => {
    window.localStorage.setItem("zoom-jwt", t);
  }, token);
  await page.goto("/");

  return { email, displayName: options.displayName, token };
}

/** UI 経由 signup / login (capture 用 / hydration 待機を厚めに入れる) */
export async function signupAndLoginViaUI(
  page: Page,
  options: { displayName: string; email?: string; password?: string }
): Promise<{ email: string; displayName: string }> {
  const email = options.email ?? uniqueEmail(options.displayName.toLowerCase().replace(/\s+/g, ""));
  const password = options.password ?? "password123";

  await page.goto("/signup");
  // hydration 完了 (submit が React 経由で動く) まで待つ
  await page.waitForLoadState("networkidle");
  // submit button が click 可能か確認 (handler 添付済の signal)
  await expect(page.getByTestId("submit-button")).toBeEnabled();

  await page.getByTestId("display-name-input").fill(options.displayName);
  await page.getByTestId("email-input").fill(email);
  await page.getByTestId("password-input").fill(password);
  await page.getByTestId("submit-button").click();

  await expect(page).toHaveURL("/", { timeout: 15_000 });
  return { email, displayName: options.displayName };
}

export async function newContextWith(ctx: BrowserContext, url: string): Promise<Page> {
  const page = await ctx.newPage();
  await page.goto(url);
  return page;
}
