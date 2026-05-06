import { defineConfig, devices } from "@playwright/test";

const FRONTEND_URL = "http://127.0.0.1:3095";
const BACKEND_URL = "http://127.0.0.1:3090";
const AI_WORKER_URL = "http://127.0.0.1:8080";

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
      // Rails backend。Solid Queue は SOLID_QUEUE_IN_PUMA=1 で puma に同居させ、
      // ADR 0003 のジョブチェイン (FinalizeRecordingJob → SummarizeMeetingJob) を
      // 1 プロセスで pickup できるようにする。
      // rbenv が zsh 側で初期化されているため zsh -lc で叩く。
      command: `zsh -lc 'SOLID_QUEUE_IN_PUMA=1 INTERNAL_INGRESS_TOKEN=dev-internal-token AI_WORKER_URL=${AI_WORKER_URL} bundle exec rails s -p 3090 -b 127.0.0.1'`,
      cwd: "../backend",
      url: `${BACKEND_URL}/up`,
      reuseExistingServer: true,
      timeout: 180_000,
    },
    {
      command: ".venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8080",
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
