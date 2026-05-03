import { test, expect } from "@playwright/test";

// ADR 0003 / 0004 / 0005 — Playwright で QueryConsole を駆動して
//   POST /queries → stream_url 取得 → fetch ReadableStream で SSE 受信 →
//   引用付き回答が body として徐々に表示されるところまでを e2e で確認する.
//
// このテストは backend の dev seeds (X-User-Id=1, sources/chunks 投入済み) に依存する.
// frontend は QueryConsole が "/" にマウントされている前提.

test("クエリ送信 → SSE chunk 受信 → 引用ハイライト表示", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: /Perplexity-lab/ })).toBeVisible();

  const textarea = page.getByRole("textbox");
  await textarea.fill("東京タワーはいつ完成した？");

  await page.getByRole("button", { name: /クエリを実行/ }).click();

  // SSE 受信中バッジが表示される (ADR 0003 §B 領域)
  await expect(page.getByText(/SSE 受信中…|完了/)).toBeVisible({ timeout: 30_000 });

  // body が徐々に増えてくる: 何かしら本文が現れることを待つ
  const article = page.locator("article");
  await expect(article).toBeVisible({ timeout: 30_000 });
  await expect(article).not.toBeEmpty();

  // 最終的に "完了" バッジが出る (event:done を受信した後)
  await expect(page.getByText(/完了/)).toBeVisible({ timeout: 60_000 });

  // 引用 1 件以上 valid として表示される (ADR 0004: Rails 側で再検証通過分のみ event:citation)
  // CitationList の見出しに「(N 件 valid / M 件 invalid)」が出る
  await expect(page.getByText(/件 valid/)).toBeVisible();

  // 引用ボタン ([#src_<n>]) が article 内にレンダリングされる
  const citationButtons = article.getByRole("button", { name: /#src_/ });
  await expect(citationButtons.first()).toBeVisible();
});

test("空クエリは送信できない (UI バリデーション or backend 422)", async ({ page }) => {
  await page.goto("/");

  const textarea = page.getByRole("textbox");
  await textarea.fill("");

  // submit しても error バッジが出るか、submitting で止まる.
  // backend は text 必須 (ParameterMissing → 400) のはず.
  await page.getByRole("button", { name: /クエリを実行/ }).click();

  // 「エラー」バッジが出ることを確認
  await expect(page.getByText(/エラー/)).toBeVisible({ timeout: 10_000 });
});
