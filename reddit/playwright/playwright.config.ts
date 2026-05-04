import { defineConfig, devices } from "@playwright/test";
import * as path from "path";

const FRONTEND_URL = "http://localhost:3065";
const BACKEND_URL = "http://localhost:3070";
const AI_WORKER_URL = "http://localhost:8060";

// E2E では sqlite ファイルを使用し docker MySQL 依存を切る (local-only)。
// backend と ai-worker が同じファイルを共有する想定だが、ai-worker は
// scheduler を無効化するので write 競合は起きない。
const SQLITE_PATH = path.resolve(__dirname, "./e2e.db");
const SQLITE_URL = `sqlite+aiosqlite:///${SQLITE_PATH}`;

const BACKEND_ENV = `DATABASE_URL=${SQLITE_URL} JWT_SECRET=e2e-secret AI_WORKER_URL=${AI_WORKER_URL}`;
const AI_WORKER_ENV = `DATABASE_URL=${SQLITE_URL} ENABLE_SCHEDULER=false`;

export default defineConfig({
  testDir: "./tests",
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: 0,
  workers: 1,
  timeout: 60_000,
  reporter: process.env.CI ? "github" : [["list"], ["html", { open: "never" }]],

  use: {
    baseURL: FRONTEND_URL,
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    // PLAYWRIGHT_VIDEO=on で常時録画モード (capture スクリプト用)。
    // 通常実行は failure のときだけ録画する。
    video: process.env.PLAYWRIGHT_VIDEO === "on" ? "on" : "retain-on-failure",
  },

  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],

  webServer: [
    {
      command: `bash -lc 'rm -f ${SQLITE_PATH} && source .venv/bin/activate && ${BACKEND_ENV} python -m app.cli migrate && ${BACKEND_ENV} uvicorn app.main:app --port 3070'`,
      cwd: "../backend",
      url: `${BACKEND_URL}/health`,
      reuseExistingServer: !process.env.CI,
      timeout: 120_000,
    },
    {
      command: `bash -lc 'source .venv/bin/activate && ${AI_WORKER_ENV} uvicorn app.main:app --port 8060'`,
      cwd: "../ai-worker",
      url: `${AI_WORKER_URL}/health`,
      reuseExistingServer: !process.env.CI,
      timeout: 60_000,
    },
    {
      command: "npm run dev",
      cwd: "../frontend",
      url: FRONTEND_URL,
      reuseExistingServer: !process.env.CI,
      timeout: 60_000,
    },
  ],
});
