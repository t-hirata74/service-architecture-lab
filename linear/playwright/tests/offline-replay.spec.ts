import { expect, test } from '@playwright/test';
import { card, createIssue, newDevice, openSecondDevice, signupViaUi } from './helpers';

/**
 * ADR 0003: オフライン編集は pending queue (IndexedDB) に積まれ、
 * 復帰時に catch-up → replay され、他デバイスへ確定値が届く。
 */
test('オフライン編集が復帰後に replay され別デバイスへ届く', async ({ browser }) => {
  const ctxA = await newDevice(browser);
  const a = await ctxA.newPage();
  const session = await signupViaUi(a, 'Alice');
  const { context: ctxB, page: b } = await openSecondDevice(browser, session);

  // A をオフライン化 (navigator offline イベント → engine.setOnline(false))
  await ctxA.setOffline(true);
  await expect(a.getByTestId('sync-status')).toContainText('オフライン');

  // オフライン中の編集: 楽観反映 + 保存中バッジ。server には届いていない
  await createIssue(a, 'Backlog', 'Offline draft');
  await expect(card(a, 'Offline draft')).toBeVisible();
  await expect(card(a, 'Offline draft')).toContainText('保存中');
  await b.waitForTimeout(800);
  await expect(card(b, 'Offline draft')).toHaveCount(0);

  // 復帰 → replay (clientMutationId 冪等) → A で確定番号が付き、B にも届く
  await ctxA.setOffline(false);
  await expect(
    card(a, 'Offline draft').getByTestId('issue-identifier'),
  ).toHaveText('GEN-1', { timeout: 15_000 });
  await expect(card(b, 'Offline draft')).toBeVisible({ timeout: 15_000 });

  await ctxB.close();
  await ctxA.close();
});
