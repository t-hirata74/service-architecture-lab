# linear backend (NestJS)

NestJS + Prisma + zod (shared スキーマ) の backend。起動・テスト手順や設計は [`../README.md`](../README.md) と [`../docs/architecture.md`](../docs/architecture.md) を参照。

- 書き込みは `POST /mutations` の 1 入口のみ (ADR 0001)
- sync log 採番は `src/sync/sync.service.ts` (workspace 行 FOR UPDATE / ADR 0002)
- e2e は `npm run test:e2e` (linear_test DB / --runInBand)
