import { defineConfig, devices } from "@playwright/test";

const FRONTEND_URL = "http://localhost:3005";
const BACKEND_URL = "http://localhost:3000";

export default defineConfig({
  testDir: "./tests",
  fullyParallel: false, // ローカル DB を共有するため直列実行
  forbidOnly: !!process.env.CI,
  retries: 0,
  workers: 1,
  reporter: process.env.CI ? "github" : [["list"], ["html", { open: "never" }]],

  use: {
    baseURL: FRONTEND_URL,
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
  },

  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
  ],

  webServer: [
    {
      command: "bundle exec rails server -p 3000 -e development",
      cwd: "../backend",
      url: `${BACKEND_URL}/up`,
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
