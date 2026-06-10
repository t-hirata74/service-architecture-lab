import { SetMetadata } from '@nestjs/common';

export const IS_PUBLIC_KEY = 'isPublic';

/** JwtAuthGuard (APP_GUARD) をバイパスする公開 endpoint の明示マーカー */
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);
