import { defineConfig, devices } from "@playwright/test";

const FRONTEND_URL = "http://localhost:3085";
const BACKEND_URL = "http://localhost:3090";
const MOCK_RECEIVER_URL = "http://localhost:4321"; // host の :4000 が他で塞がっている前提

const DEMO_SECRET = "demo-shared-secret-do-not-use-in-prod";

export default defineConfig({
  testDir: "./tests",
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: 0,
  workers: 1,
  timeout: 90_000,
  reporter: process.env.CI ? "github" : [["list"], ["html", { open: "never" }]],

  // ADR 0004: Solid Queue worker (`bin/jobs`) を spawn して webhook 配信を pickup させる。
  // webServer に出来ない (worker は port を持たない) ので globalSetup で起動する。
  globalSetup: require.resolve("./scripts/global-setup.ts"),
  globalTeardown: require.resolve("./scripts/global-teardown.ts"),

  use: {
    baseURL: FRONTEND_URL,
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    video: process.env.PLAYWRIGHT_VIDEO === "on" ? "on" : "retain-on-failure",
  },

  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],

  webServer: [
    {
      // Rails backend (起動前に seed を流して on_hand=1 など demo state をリセット)
      // rbenv は zsh に init されている (bash login shell では拾えない) ので zsh -lc で起動。
      command: `zsh -lc 'MOCK_RECEIVER_URL=${MOCK_RECEIVER_URL}/webhooks/shopify bin/rails db:seed >/dev/null && bin/rails s -p 3090 -b 127.0.0.1'`,
      cwd: "../backend",
      url: `${BACKEND_URL}/up`,
      reuseExistingServer: true,
      timeout: 180_000,
    },
    {
      command: `zsh -lc 'PORT=4321 DEMO_APP_SECRET=${DEMO_SECRET} bundle exec ruby app.rb'`,
      cwd: "../apps/mock_receiver",
      url: `${MOCK_RECEIVER_URL}/api/deliveries`,
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
