import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { TriageRequestSchema } from '@linear/shared';
import type { TriageRequest, TriageResponse } from '@linear/shared';
import { CurrentUser } from '../common/current-user.decorator';
import type { AuthUser } from '../common/current-user.decorator';
import { ZodValidationPipe } from '../common/zod-validation.pipe';
import { AiService } from './ai.service';

@Controller('ai')
export class AiController {
  constructor(private readonly ai: AiService) {}

  @Post('triage')
  @HttpCode(200)
  triage(
    @CurrentUser() user: AuthUser,
    @Body(new ZodValidationPipe(TriageRequestSchema)) body: TriageRequest,
  ): Promise<TriageResponse> {
    return this.ai.triage(user.userId, body);
  }
}
