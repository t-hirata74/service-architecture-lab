import { expect, test } from '@playwright/test';
import { card, column, createIssue, newDevice, openSecondDevice, signupViaUi } from './helpers';

/**
 * ADR 0005: mutation の確定 op が WS で同一 workspace の他接続へ fan-out される。
 * Device A (左) で作成・移動 → Device B (右) に server 確定値が映る。
 */
test('issue 作成と移動が別デバイスへリアルタイム反映される', async ({ browser }) => {
  const ctxA = await newDevice(browser);
  const a = await ctxA.newPage();
  const session = await signupViaUi(a, 'Alice');
  const { context: ctxB, page: b } = await openSecondDevice(browser, session);

  // A: 楽観反映 → server 確定で番号 (GEN-1) が付く
  await createIssue(a, 'Backlog', 'Realtime hello');
  await expect(card(a, 'Realtime hello')).toBeVisible();
  await expect(
    card(a, 'Realtime hello').getByTestId('issue-identifier'),
  ).toHaveText('GEN-1');

  // B: WS push (op) で届く
  await expect(card(b, 'Realtime hello')).toBeVisible();
  await expect(
    column(b, 'Backlog').locator('[data-testid="issue-card"]'),
  ).toHaveCount(1);

  // A で → (Todo へ移動) → B の Todo 列へ動く
  await card(a, 'Realtime hello').hover();
  await card(a, 'Realtime hello').getByTestId('move-right').click();
  await expect(
    column(b, 'Todo').locator('[data-issue-title="Realtime hello"]'),
  ).toBeVisible();
  await expect(
    column(b, 'Backlog').locator('[data-testid="issue-card"]'),
  ).toHaveCount(0);

  await ctxB.close();
  await ctxA.close();
});
