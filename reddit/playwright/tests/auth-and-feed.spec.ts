import { test, expect, Page } from "@playwright/test";

const BACKEND_URL = "http://localhost:3070";

/**
 * 同一 sqlite ファイルを複数テスト間で共有するので、ユーザ名は test 毎に
 * 一意にする必要がある。
 */
function uniqueUser(prefix: string): string {
  return `${prefix}_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
}

async function registerViaApi(page: Page, username: string): Promise<string> {
  const res = await page.request.post(`${BACKEND_URL}/auth/register`, {
    data: { username, password: "secret123" },
  });
  expect(res.status(), `register ${username}`).toBe(201);
  const body = await res.json();
  return body.access_token as string;
}

/** localStorage に token / user をセットしてから対象ページに遷移する。 */
async function loginAs(page: Page, username: string): Promise<void> {
  const token = await registerViaApi(page, username);
  await page.goto("/");
  await page.evaluate(
    ({ token, username }) => {
      window.localStorage.setItem("reddit-token", token);
      window.localStorage.setItem(
        "reddit-user",
        JSON.stringify({ id: 0, username, created_at: "" }),
      );
    },
    { token, username },
  );
  await page.reload();
}

test("anonymous 閲覧: subreddit 一覧が表示される", async ({ page }) => {
  const owner = uniqueUser("anon_seed");
  const token = await registerViaApi(page, owner);
  const sub = `anon_${Date.now()}`;
  const created = await page.request.post(`${BACKEND_URL}/r`, {
    headers: { Authorization: `Bearer ${token}` },
    data: { name: sub, description: "anonymous-readable subreddit" },
  });
  expect(created.status()).toBe(201);

  await page.goto("/");
  await expect(page.getByRole("heading", { name: "subreddits" })).toBeVisible();
  await expect(page.getByRole("link", { name: `r/${sub}` })).toBeVisible();
});

test("認証フロー: 登録 → subreddit → post → upvote → コメント → 返信", async ({ page }) => {
  const username = uniqueUser("e2e_user");
  const subName = `e2etest_${Date.now()}`;

  await loginAs(page, username);

  // subreddit 作成
  await page.goto("/");
  await page.getByPlaceholder("name (a-z, 0-9, _)").fill(subName);
  await page.getByPlaceholder("description").fill("e2e test subreddit");
  await page.getByRole("button", { name: "create" }).click();
  await expect(page.getByRole("link", { name: `r/${subName}` })).toBeVisible();

  // subreddit ページに移動して post を作成
  await page.getByRole("link", { name: `r/${subName}` }).click();
  await page.getByPlaceholder("post title").fill("e2e first post");
  await page.getByPlaceholder("body (optional)").fill("hello world from playwright");
  await page.getByRole("button", { name: "post" }).click();
  await expect(page.getByRole("link", { name: "e2e first post" })).toBeVisible();

  // post 詳細に移動して upvote
  await page.getByRole("link", { name: "e2e first post" }).click();
  await expect(page.getByRole("heading", { name: "e2e first post" })).toBeVisible();
  // initial score は 0、upvote 後は 1
  await expect(page.locator(".tabular-nums").first()).toHaveText("0");
  await page.getByRole("button", { name: "upvote" }).first().click();
  await expect(page.locator(".tabular-nums").first()).toHaveText("1");

  // top-level comment を投稿
  await page.getByPlaceholder("add a comment").fill("first comment");
  await page.getByRole("button", { name: "comment" }).click();
  await expect(page.getByText("first comment")).toBeVisible();

  // depth 1 / path が表示されている
  await expect(page.getByText(/^depth 1$/)).toBeVisible();

  // reply
  await page.getByRole("button", { name: "reply" }).first().click();
  await page.getByPlaceholder("reply...").fill("nested reply");
  await page.getByRole("button", { name: "post reply" }).click();
  await expect(page.getByText("nested reply")).toBeVisible();
  await expect(page.getByText(/^depth 2$/)).toBeVisible();
});

test("ai-worker proxy: TL;DR を取得して表示する", async ({ page }) => {
  const username = uniqueUser("e2e_ai");
  const subName = `e2eai_${Date.now()}`;
  await loginAs(page, username);

  // post を 1 件作成
  await page.goto("/");
  await page.getByPlaceholder("name (a-z, 0-9, _)").fill(subName);
  await page.getByRole("button", { name: "create" }).click();
  await expect(page.getByRole("link", { name: `r/${subName}` })).toBeVisible();
  await page.getByRole("link", { name: `r/${subName}` }).click();
  await page.getByPlaceholder("post title").fill("FastAPI tutorial post");
  await page.getByPlaceholder("body (optional)").fill("python python python fastapi async tutorial");
  await page.getByRole("button", { name: "post" }).click();

  await page.getByRole("link", { name: "FastAPI tutorial post" }).click();
  await page.getByRole("button", { name: /TL;DR/i }).click();
  await expect(page.getByText(/TL;DR:/)).toBeVisible();
  // 「keywords:」は TL;DR 行と keywords 行の 2 箇所に出るので first を取る
  await expect(page.getByText(/keywords:/).first()).toBeVisible();
});
