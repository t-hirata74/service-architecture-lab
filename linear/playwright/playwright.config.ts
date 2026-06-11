import { defineConfig, devices } from '@playwright/test';

const FRONTEND_URL = 'http://127.0.0.1:3145';
const BACKEND_URL = 'http://127.0.0.1:3140';

// 実機フルスタック E2E (zoom と同方針):
// - 前提: mysql :3330 が起動済み (`docker compose up -d` / make linear-deps-up)
// - backend / frontend は webServer が production build で起動する
//   (frontend を next start にするのは hydration race 回避 / testing-strategy.md)
const backendCmd =
  "sh -c 'npm run build >/dev/null && (cd backend && npx prisma migrate deploy) && node backend/dist/main.js'";
const frontendCmd = "sh -c 'npm run build -w frontend >/dev/null && npm run start -w frontend'";

export default defineConfig({
  testDir: './tests',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: 0,
  workers: 1,
  timeout: 120_000,
  reporter: process.env.CI ? 'github' : [['list'], ['html', { open: 'never' }]],

  use: {
    baseURL: FRONTEND_URL,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: process.env.PLAYWRIGHT_VIDEO === 'on' ? 'on' : 'retain-on-failure',
    viewport: { width: 640, height: 720 }, // hstack gif 用に 2 context を並べられる幅
  },

  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'], viewport: { width: 640, height: 720 } } }],

  webServer: [
    {
      command: backendCmd,
      cwd: '..',
      url: `${BACKEND_URL}/health`,
      reuseExistingServer: true,
      timeout: 240_000,
    },
    {
      command: frontendCmd,
      cwd: '..',
      url: FRONTEND_URL,
      reuseExistingServer: true,
      timeout: 240_000,
    },
  ],
});
