import { createParamDecorator, ExecutionContext } from '@nestjs/common';

export interface AuthUser {
  userId: number;
}

interface RequestWithUser {
  user?: AuthUser;
}

/** JwtAuthGuard が req.user に載せた認証主体を取り出す */
export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): AuthUser => {
    const req = ctx.switchToHttp().getRequest<RequestWithUser>();
    if (!req.user) {
      throw new Error('CurrentUser used on unauthenticated route');
    }
    return req.user;
  },
);
