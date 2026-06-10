import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { MutationRequestSchema } from '@linear/shared';
import type { MutationRequest, MutationResponse } from '@linear/shared';
import { CurrentUser } from '../common/current-user.decorator';
import type { AuthUser } from '../common/current-user.decorator';
import { ZodValidationPipe } from '../common/zod-validation.pipe';
import { MutationsService } from './mutations.service';

@Controller('mutations')
export class MutationsController {
  constructor(private readonly mutations: MutationsService) {}

  @Post()
  @HttpCode(200)
  execute(
    @CurrentUser() user: AuthUser,
    @Body(new ZodValidationPipe(MutationRequestSchema)) body: MutationRequest,
  ): Promise<MutationResponse> {
    return this.mutations.execute(user.userId, body);
  }
}
