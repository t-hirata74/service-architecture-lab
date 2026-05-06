import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

/**
 * Solid Queue worker (bin/jobs) と DB の demo state リセットをセットアップで行う。
 *
 * - bin/jobs: ADR 0004 webhook 配信を pickup する。port を持たないので
 *   webServer 経由では起動できず、ここで spawn して PID を test-results/ に書き出し、
 *   teardown で kill する。
 * - rails runner: 各 spec が独立した state で走るよう、orders / cart / movement /
 *   delivery を消し on_hand を seeds.rb の値 (limited=1 等) に戻す。
 */

export default async function globalSetup() {
  const root = join(__dirname, "..");
  mkdirSync(join(root, "test-results"), { recursive: true });

  // 1) demo state リセット (orders / movements / deliveries を消し、seed で on_hand=1 を戻す)
  await runOnce("rails-reset", "zsh", [
    "-lc",
    `bin/rails runner '
      Orders::OrderItem.delete_all
      Orders::Order.delete_all
      Orders::CartItem.delete_all
      Orders::Cart.delete_all
      Inventory::StockMovement.delete_all
      Apps::WebhookDelivery.delete_all
      Core::Shop.update_all(next_order_number: 1)
      Core::User.delete_all
      Core::Account.delete_all
    ' >/dev/null && MOCK_RECEIVER_URL=http://localhost:4321/webhooks/shopify bin/rails db:seed >/dev/null`,
  ], { cwd: join(root, "..", "backend") });

  // 2) bin/jobs を spawn (Solid Queue worker)
  const jobsLog = join(root, "test-results", "bin-jobs.log");
  const jobs = spawn("zsh", ["-lc", `bin/jobs >> ${jobsLog} 2>&1`], {
    cwd: join(root, "..", "backend"),
    detached: true,
    stdio: "ignore",
  });
  jobs.unref();
  writeFileSync(join(root, "test-results", "bin-jobs.pid"), String(jobs.pid));
  // worker が pickup を始めるまで少し待つ
  await new Promise((r) => setTimeout(r, 1500));
  console.log(`[global-setup] bin/jobs spawned pid=${jobs.pid} (log: ${jobsLog})`);
}

function runOnce(label: string, cmd: string, args: string[], opts: { cwd: string }): Promise<void> {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, { ...opts, stdio: "inherit" });
    p.on("exit", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`[global-setup] ${label} exited with ${code}`));
    });
  });
}
