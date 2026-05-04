import { defineConfig, devices } from "@playwright/test";

const FRONTEND_URL = "http://localhost:3055";
const BACKEND_URL = "http://localhost:3060";
const AI_WORKER_URL = "http://localhost:8050";

// Heartbeat を短縮して slow consumer / heartbeat-loss シナリオが秒単位で観測できるように
// する。production は 10000ms 想定 (ADR 0003)。
const BACKEND_ENV = "HEARTBEAT_INTERVAL_MS=2000 HTTP_ADDR=:3060";

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
      command: `bash -lc '${BACKEND_ENV} go run ./cmd/server/migrate && ${BACKEND_ENV} AI_WORKER_URL=${AI_WORKER_URL} go run ./cmd/server'`,
      cwd: "../backend",
      url: `${BACKEND_URL}/health`,
      reuseExistingServer: true,
      timeout: 120_000,
    },
    {
      command:
        "bash -lc 'source .venv/bin/activate && uvicorn main:app --port 8050'",
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
