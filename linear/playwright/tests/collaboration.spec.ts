import { expect, test } from '@playwright/test';
import { card, createIssue, newDevice, signupViaUi } from './helpers';

/**
 * E1 (ADR 0006): 招待による本物のマルチユーザ協調。
 * alice (左) が bob を email で招待 → bob (右) は workspace switcher で
 * alice の workspace へ切替 → alice の issue 作成が bob へ realtime 反映。
 */
test('招待した別ユーザの workspace 切替先へ issue がリアルタイム反映される', async ({
  browser,
}) => {
  // bob: 先に signup して自分の board に居る (email は session から拾う)
  const ctxB = await newDevice(browser);
  const b = await ctxB.newPage();
  const bobSession = JSON.parse(await signupViaUi(b, 'Bob')) as {
    user: { email: string };
  };

  // alice: signup → members パネルから bob を招待
  const ctxA = await newDevice(browser);
  const a = await ctxA.newPage();
  await signupViaUi(a, 'Alice');
  await a.getByTestId('members-button').click();
  await a.getByTestId('invite-email').fill(bobSession.user.email);
  await a.getByTestId('invite-submit').click();
  await expect(a.locator('[data-testid="member-row"]')).toHaveCount(2);
  await expect(
    a.locator('[data-member-name="Bob"] >> text=member'),
  ).toBeVisible();
  await a.keyboard.press('Escape');

  // bob: switcher で alice の workspace を発見して切替
  await b.getByTestId('workspace-switcher').click();
  await b
    .getByTestId('workspace-option')
    .filter({ hasText: 'Alice Workspace' })
    .click();
  await expect(b.getByTestId('sync-status')).toBeVisible();
  await expect(b.getByTestId('members-button')).toHaveText(/メンバー 2/);

  // alice の作成が bob (member) へ WS push で届く
  await createIssue(a, 'Backlog', 'Hello Bob');
  await expect(card(b, 'Hello Bob')).toBeVisible();

  await ctxB.close();
  await ctxA.close();
});
