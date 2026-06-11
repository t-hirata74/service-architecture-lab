import { Browser, BrowserContext, expect, Page } from '@playwright/test';

/**
 * 手動生成 context は config の use.video を継承しないため、
 * 録画時 (PLAYWRIGHT_VIDEO=on) はここで recordVideo を付与する。
 */
export function newDevice(browser: Browser): Promise<BrowserContext> {
  return browser.newContext(
    process.env.PLAYWRIGHT_VIDEO === 'on'
      ? { recordVideo: { dir: 'test-results/videos', size: { width: 640, height: 720 } } }
      : {},
  );
}

/** UI から signup して board 到達まで待ち、session JSON を返す */
export async function signupViaUi(page: Page, name: string): Promise<string> {
  const email = `e2e-${Date.now()}-${Math.floor(Math.random() * 1e6)}@example.com`;
  await page.goto('/login');
  await page.getByTestId('name').fill(name);
  await page.getByTestId('email').fill(email);
  await page.getByTestId('password').fill('password123');
  await page.getByTestId('submit').click();
  await expect(page.getByTestId('sync-status')).toBeVisible();
  return page.evaluate(() => localStorage.getItem('linear.session') as string);
}

/** 同じ session を注入した「2 台目のデバイス」context を開く */
export async function openSecondDevice(
  browser: Browser,
  sessionJson: string,
): Promise<{ context: BrowserContext; page: Page }> {
  const context = await newDevice(browser);
  await context.addInitScript(
    (s: string) => localStorage.setItem('linear.session', s),
    sessionJson,
  );
  const page = await context.newPage();
  await page.goto('/board');
  await expect(page.getByTestId('sync-status')).toBeVisible();
  return { context, page };
}

export async function createIssue(
  page: Page,
  columnName: string,
  title: string,
): Promise<void> {
  await page.getByTestId(`new-issue-${columnName}`).click();
  await page.getByTestId('new-issue-title').fill(title);
  await page.getByTestId('new-issue-submit').click();
}

export function card(page: Page, title: string) {
  return page.locator(`[data-testid="issue-card"][data-issue-title="${title}"]`);
}

export function column(page: Page, name: string) {
  return page.locator(`[data-testid="board-column"][data-column-name="${name}"]`);
}
