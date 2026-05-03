import { defineConfig, devices } from "@playwright/test";

const FRONTEND_URL = "http://localhost:3035";
const BACKEND_URL = "http://localhost:3040";
const AI_WORKER_URL = "http://localhost:8030";

export default defineConfig({
  testDir: "./tests",
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: 0,
  workers: 1,
  // SSE は数秒〜十数秒かかるため、デフォルトより長めの timeout を確保 (ADR 0003).
  timeout: 60_000,
  reporter: process.env.CI ? "github" : [["list"], ["html", { open: "never" }]],

  use: {
    baseURL: FRONTEND_URL,
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    video: "retain-on-failure"
  },

  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],

  webServer: [
    {
      command: "bundle exec rails server -p 3040 -e development",
      cwd: "../backend",
      url: `${BACKEND_URL}/health`,
      reuseExistingServer: true,
      timeout: 60_000
    },
    {
      command: "bash -lc 'source .venv/bin/activate && uvicorn main:app --port 8030'",
      cwd: "../ai-worker",
      url: `${AI_WORKER_URL}/health`,
      reuseExistingServer: true,
      timeout: 60_000
    },
    {
      command: "npm run dev",
      cwd: "../frontend",
      url: FRONTEND_URL,
      reuseExistingServer: true,
      timeout: 60_000
    }
  ]
});
