import { Page, expect } from "@playwright/test";

export function uniqueEmail(prefix: string = "user"): string {
  const tag = Math.random().toString(36).slice(2, 10);
  return `${prefix}-${tag}@e2e.test`;
}

export function uniqueChannelName(prefix: string = "ch"): string {
  return `${prefix}-${Math.random().toString(36).slice(2, 8)}`;
}

export async function signupViaUI(page: Page, opts: { displayName: string; email: string; password: string }) {
  await page.goto("/signup");
  await page.getByLabel("表示名").fill(opts.displayName);
  await page.getByLabel("メールアドレス").fill(opts.email);
  await page.getByLabel(/パスワード/).fill(opts.password);
  await page.getByRole("button", { name: "登録する" }).click();
  await expect(page).toHaveURL(/\/channels$/);
}

export async function loginViaUI(page: Page, opts: { email: string; password: string }) {
  await page.goto("/login");
  await page.getByLabel("メールアドレス").fill(opts.email);
  await page.getByLabel("パスワード").fill(opts.password);
  await page.getByRole("button", { name: "ログイン" }).click();
  await expect(page).toHaveURL(/\/channels$/);
}
