import { defineConfig, devices } from "@playwright/test";

const FRONTEND_URL = "http://127.0.0.1:3135";
const BACKEND_URL = "http://127.0.0.1:3130";
const DSN = "datadog:datadog@tcp(host.docker.internal:3329)/datadog_development?parseTime=true&multiStatements=true";
const CI_DSN = "datadog:datadog@tcp(127.0.0.1:3306)/datadog_development?parseTime=true&multiStatements=true";

// E2E は flush/eval を速くするため WINDOW_SECONDS=1 / EVAL_INTERVAL_SEC=1。
// backend は host に Go が無いので local は docker golang:1.25、CI は setup-go の native go (uber と同方針)。
const backendEnv = "HTTP_ADDR=:3130 WINDOW_SECONDS=1 EVAL_INTERVAL_SEC=1 INGEST_API_KEY=dev-ingest-key";
const localBackend =
  `docker run --rm -v "$PWD":/app -w /app -v datadog_gomod:/go/pkg/mod -p 3130:3130 ` +
  `-e DATABASE_URL='${DSN}' -e ${backendEnv.split(" ").join(" -e ")} ` +
  `golang:1.25 sh -c 'go run ./cmd/server/migrate && go run ./cmd/server'`;
const ciBackend =
  `env DATABASE_URL='${CI_DSN}' ${backendEnv} ` +
  `sh -c 'go run ./cmd/server/migrate && go run ./cmd/server'`;

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
      command: process.env.CI ? ciBackend : localBackend,
      cwd: "../backend",
      url: `${BACKEND_URL}/healthz`,
      reuseExistingServer: true,
      timeout: 240_000,
    },
    {
      command: "npm run start",
      cwd: "../frontend",
      url: FRONTEND_URL,
      reuseExistingServer: true,
      timeout: 60_000,
    },
  ],
});
