import { defineConfig, devices } from "@playwright/test";

const FRONTEND_URL = "http://127.0.0.1:3125";
const BACKEND_URL = "http://127.0.0.1:3120";
const AI_WORKER_URL = "http://127.0.0.1:8110";

// 本リポは host に Ruby 4 を native (rbenv) で入れている。非対話シェルは rbenv init を
// 読まないので、ローカルは rbenv shims を PATH 先頭に注入して Ruby 4.0.5 を解決する。
// CI は ruby/setup-ruby が PATH 整備済なので直接 bundle exec。
const railsCmd = (process.env.CI
  ? ""
  : 'PATH="$HOME/.rbenv/shims:$PATH" ') +
  `RAILS_ENV=development AI_WORKER_URL=${AI_WORKER_URL} AI_INTERNAL_TOKEN=dev-internal-token ` +
  "bundle exec rails s -p 3120 -b 127.0.0.1";

export default defineConfig({
  testDir: "./tests",
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: 0,
  workers: 1,
  timeout: 120_000,
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
      command: `env ${railsCmd}`,
      cwd: "../backend",
      url: `${BACKEND_URL}/up`,
      reuseExistingServer: true,
      timeout: 180_000,
    },
    {
      command: process.env.CI
        ? "env INTERNAL_TOKEN=dev-internal-token uvicorn main:app --host 127.0.0.1 --port 8110"
        : "env INTERNAL_TOKEN=dev-internal-token .venv/bin/uvicorn main:app --host 127.0.0.1 --port 8110",
      cwd: "../ai-worker",
      url: `${AI_WORKER_URL}/health`,
      reuseExistingServer: true,
      timeout: 60_000,
    },
    {
      // production build (npm run start) で hydration race を回避 (calendly/zoom と同方針)。
      command: "npm run start",
      cwd: "../frontend",
      url: FRONTEND_URL,
      reuseExistingServer: true,
      timeout: 60_000,
    },
  ],
});
