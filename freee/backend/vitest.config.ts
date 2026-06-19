import { defineConfig } from 'vitest/config';

// DB を共有する統合テストなので、ファイル並列を切って直列化する
// (datadog の go test -p 1 と同じ理由: 並列が同一 DB を干渉させる)。
export default defineConfig({
  test: {
    fileParallelism: false,
    hookTimeout: 30000,
    testTimeout: 30000,
  },
});
