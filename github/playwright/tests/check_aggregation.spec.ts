import { test, expect, request as pwRequest } from "@playwright/test";
import { setViewerInBrowser, SEED } from "./helpers";

// ai-worker → backend `/internal/commit_checks` upsert → GraphQL の集約値が UI バッジに反映されるまでを通す
test("ai-worker check/run drives PullRequest.checkStatus aggregation", async ({ page }) => {
  await setViewerInBrowser(page, "alice");

  // 既存の check を一掃するため、build と test を success で打ち、最後に lint を失敗にする
  const ai = await pwRequest.newContext({ baseURL: "http://localhost:8020" });

  for (const [name, force] of [
    ["build", "success"],
    ["test", "success"]
  ] as const) {
    const res = await ai.post("/check/run", {
      data: { owner: SEED.org, name: SEED.repo, head_sha: SEED.prHeadSha, check_name: name, force_state: force }
    });
    expect(res.ok()).toBeTruthy();
  }

  await page.goto(`/${SEED.org}/${SEED.repo}/pull/${SEED.prNumber}`);
  // 集約: 全 success → SUCCESS バッジ
  await expect(page.getByText("SUCCESS").first()).toBeVisible();

  // lint 失敗を追加 → FAILURE に転落
  const failed = await ai.post("/check/run", {
    data: { owner: SEED.org, name: SEED.repo, head_sha: SEED.prHeadSha, check_name: "lint", force_state: "failure" }
  });
  expect(failed.ok()).toBeTruthy();

  // SPA リフェッチ。urql cache-and-network なのでリロードで最新を取得
  await page.reload();
  await expect(page.getByText("FAILURE").first()).toBeVisible();
  // テーブルに lint 行が見える (output 列にも "lint" が含まれるため exact 指定)
  await expect(page.getByRole("cell", { name: "lint", exact: true })).toBeVisible();

  await ai.dispose();
});
