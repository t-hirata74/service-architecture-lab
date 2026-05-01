import { Page } from "@playwright/test";

// 開発用 X-User-Login をブラウザ側 localStorage に仕込む。
// urqlClient.ts は localStorage から viewer login を取り出すため、
// 各テストの前に明示的にセットする必要がある。
export async function setViewerInBrowser(page: Page, login: string | null) {
  await page.addInitScript((value) => {
    if (value) {
      window.localStorage.setItem("x-user-login", value);
    } else {
      window.localStorage.removeItem("x-user-login");
    }
  }, login);
}

export const SEED = {
  org: "acme",
  repo: "tools",
  prNumber: 2,
  prHeadSha: "seedsha000000000000000000000000000000000"
};
