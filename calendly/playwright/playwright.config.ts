import { defineConfig, devices } from "@playwright/test";

const FRONTEND_URL = "http://127.0.0.1:3105";
const BACKEND_URL  = "http://127.0.0.1:3100";
const AI_WORKER_URL = "http://127.0.0.1:8090";

export default defineConfig({
  testDir: "./tests",
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: 0,
  workers: 1,
  timeout: 90_000,
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
      // Rails backend (Ruby 4.0.3 / Rails 8.1)。
      // ローカル: rbenv が zsh 側で初期化されているため zsh -lc。
      // CI: Ubuntu に zsh が無い + ruby/setup-ruby が PATH 整備済 → 直接 bundle exec。
      // (testing-strategy.md zoom Playwright 節を参照)
      command: process.env.CI
        ? `env INTERNAL_INGRESS_TOKEN=dev-internal-token AI_WORKER_URL=${AI_WORKER_URL} bundle exec rails s -p 3100 -b 127.0.0.1`
        : `zsh -lc 'INTERNAL_INGRESS_TOKEN=dev-internal-token AI_WORKER_URL=${AI_WORKER_URL} bundle exec rails s -p 3100 -b 127.0.0.1'`,
      cwd: "../backend",
      url: `${BACKEND_URL}/up`,
      reuseExistingServer: true,
      timeout: 180_000,
    },
    {
      command: process.env.CI
        ? "uvicorn app.main:app --host 127.0.0.1 --port 8090"
        : ".venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8090",
      cwd: "../ai-worker",
      url: `${AI_WORKER_URL}/health`,
      reuseExistingServer: true,
      timeout: 60_000,
    },
    {
      // dev mode は hydration が遅く、button click が React handler attach 前に native submit になる
      // race が頻発する。production build で動かすことで hydration race を回避する。
      command: "npm run start",
      cwd: "../frontend",
      url: FRONTEND_URL,
      reuseExistingServer: true,
      timeout: 60_000,
    },
  ],
});
