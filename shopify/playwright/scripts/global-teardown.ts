import { readFileSync, existsSync, unlinkSync } from "node:fs";
import { join } from "node:path";

export default async function globalTeardown() {
  const pidFile = join(__dirname, "..", "test-results", "bin-jobs.pid");
  if (!existsSync(pidFile)) return;
  const pid = Number(readFileSync(pidFile, "utf-8").trim());
  if (!pid) return;
  try {
    // negative pid → kill the whole process group (bin/jobs spawns supervisor + worker)
    process.kill(-pid, "SIGTERM");
    console.log(`[global-teardown] killed bin/jobs pgid=${pid}`);
  } catch (e) {
    try { process.kill(pid, "SIGTERM"); } catch {}
  }
  try { unlinkSync(pidFile); } catch {}
}
