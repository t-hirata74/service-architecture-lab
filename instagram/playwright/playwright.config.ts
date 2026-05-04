import { defineConfig, devices } from "@playwright/test";

const FRONTEND_URL = "http://localhost:3045";
const BACKEND_URL = "http://localhost:3050";
const AI_WORKER_URL = "http://localhost:8040";

// Celery を eager 実行にして Playwright の同期駆動で fan-out 結果を待てるようにする。
// ADR 0001: 本番では Celery worker が別プロセスで動くが、E2E では Django プロセス
// 内の同期実行に切り替えて test 安定化を優先する trade-off。
const DJANGO_ENV =
  "CELERY_TASK_ALWAYS_EAGER=True DJANGO_DEBUG=True " +
  "CORS_ALLOWED_ORIGINS=http://localhost:3045,http://127.0.0.1:3045";

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
    video: process.env.PLAYWRIGHT_VIDEO === "on" ? "on" : "retain-on-failure",
  },

  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],

  webServer: [
    {
      command: `bash -lc 'source .venv/bin/activate && ${DJANGO_ENV} python manage.py runserver 0.0.0.0:3050'`,
      cwd: "../backend",
      url: `${BACKEND_URL}/health`,
      reuseExistingServer: true,
      timeout: 60_000,
    },
    {
      command:
        "bash -lc 'source .venv/bin/activate && uvicorn main:app --port 8040'",
      cwd: "../ai-worker",
      url: `${AI_WORKER_URL}/health`,
      reuseExistingServer: true,
      timeout: 60_000,
    },
    {
      command: "npm run dev",
      cwd: "../frontend",
      url: FRONTEND_URL,
      reuseExistingServer: true,
      timeout: 60_000,
    },
  ],
});
