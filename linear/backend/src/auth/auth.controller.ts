import { Body, Controller, Get, HttpCode, Post } from '@nestjs/common';
import { LoginRequestSchema, SignupRequestSchema } from '@linear/shared';
import type { LoginRequest, SignupRequest } from '@linear/shared';
import { CurrentUser } from '../common/current-user.decorator';
import type { AuthUser } from '../common/current-user.decorator';
import { Public } from '../common/public.decorator';
import { ZodValidationPipe } from '../common/zod-validation.pipe';
import { AuthService } from './auth.service';

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Public()
  @Post('signup')
  signup(@Body(new ZodValidationPipe(SignupRequestSchema)) dto: SignupRequest) {
    return this.auth.signup(dto);
  }

  @Public()
  @Post('login')
  @HttpCode(200)
  login(@Body(new ZodValidationPipe(LoginRequestSchema)) dto: LoginRequest) {
    return this.auth.login(dto);
  }

  @Get('me')
  me(@CurrentUser() user: AuthUser) {
    return this.auth.me(user.userId);
  }
}
