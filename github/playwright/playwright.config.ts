import { defineConfig, devices } from "@playwright/test";

const FRONTEND_URL = "http://localhost:3025";
const BACKEND_URL = "http://localhost:3030";
const AI_WORKER_URL = "http://localhost:8020";

export default defineConfig({
  testDir: "./tests",
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: 0,
  workers: 1,
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
      command: "bundle exec rails server -p 3030 -e development",
      cwd: "../backend",
      url: `${BACKEND_URL}/health`,
      reuseExistingServer: true,
      timeout: 60_000,
      env: { INTERNAL_INGRESS_TOKEN: "dev-internal-token" }
    },
    {
      command: "bash -lc 'source .venv/bin/activate && uvicorn main:app --port 8020'",
      cwd: "../ai-worker",
      url: `${AI_WORKER_URL}/health`,
      reuseExistingServer: true,
      timeout: 60_000,
      env: { BACKEND_URL: BACKEND_URL, INTERNAL_INGRESS_TOKEN: "dev-internal-token" }
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
