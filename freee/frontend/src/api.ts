import { hc } from 'hono/client';
import type { AppType } from '@freee/backend/app';

/**
 * Hono RPC クライアント (ADR 0004)。codegen 無しに backend のルート型を共有する。
 * `import type` なので backend の実行コードは frontend に混入しない (型だけ消える)。
 *
 * tenant は Phase 2 ではヘッダ x-company-id で渡す (Phase 4 で認証セッションへ)。
 */
export function makeClient(companyId: number) {
  return hc<AppType>('/', {
    headers: { 'x-company-id': String(companyId) },
  });
}
