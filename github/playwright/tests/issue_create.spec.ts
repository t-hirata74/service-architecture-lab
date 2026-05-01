import { test, expect, request as pwRequest } from "@playwright/test";
import { SEED, setViewerInBrowser } from "./helpers";

// GraphQL Mutation `createIssue` を直接叩いて、UI 一覧に新規 issue が反映されることを確認。
// (Mutation 用 UI は Phase 5b では未実装のため、API 経路で検証 → repository ページで一覧を確認)
test("createIssue mutation appears in repository issues list", async ({ page }) => {
  await setViewerInBrowser(page, "alice");

  const api = await pwRequest.newContext({ baseURL: "http://localhost:3030" });
  const title = `E2E ${Date.now()}`;
  const res = await api.post("/graphql", {
    headers: { "Content-Type": "application/json", "X-User-Login": "alice" },
    data: {
      query: `mutation($o:String!,$n:String!,$t:String!){
        createIssue(input:{ owner:$o, name:$n, title:$t, body:"" }) {
          issue { number title } errors
        }
      }`,
      variables: { o: SEED.org, n: SEED.repo, t: title }
    }
  });
  const body = await res.json();
  expect(body.data.createIssue.errors).toEqual([]);
  expect(body.data.createIssue.issue.title).toBe(title);

  await page.goto(`/${SEED.org}/${SEED.repo}`);
  await expect(page.getByText(title)).toBeVisible();

  await api.dispose();
});
