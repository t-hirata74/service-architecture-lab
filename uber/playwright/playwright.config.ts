import { defineConfig, devices } from "@playwright/test";

const FRONTEND_URL = "http://localhost:3115";
const BACKEND_URL = "http://localhost:3110";
const AI_WORKER_URL = "http://localhost:8100";

// backend は CGO 必須 (h3-go)。go が host に無い環境では、先に docker の golang
// コンテナ等で :3110 を立てておけば reuseExistingServer: true で再利用される
// (webServer の go run はスキップされる)。CI の uber-playwright ジョブは
// typecheck のみで webServer は起動しない。
const BACKEND_ENV = `HTTP_ADDR=127.0.0.1:3110 AI_WORKER_URL=${AI_WORKER_URL} AI_INTERNAL_TOKEN=dev-internal-token`;

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
      command: `bash -lc 'go run ./cmd/migrate && ${BACKEND_ENV} go run ./cmd/dispatch'`,
      cwd: "../backend",
      url: `${BACKEND_URL}/healthz`,
      reuseExistingServer: true,
      timeout: 120_000,
    },
    {
      command:
        "bash -lc 'source .venv/bin/activate && INTERNAL_TOKEN=dev-internal-token uvicorn main:app --port 8100'",
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
