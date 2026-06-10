import { Controller, Get, Query } from '@nestjs/common';
import type { BootstrapResponse, DeltaResponse } from '@linear/shared';
import { CurrentUser } from '../common/current-user.decorator';
import type { AuthUser } from '../common/current-user.decorator';
import { ZodValidationPipe } from '../common/zod-validation.pipe';
import { WorkspacesService } from '../workspaces/workspaces.service';
import { BootstrapQuerySchema, DeltaQuerySchema } from './query-schemas';
import type { BootstrapQuery, DeltaQuery } from './query-schemas';
import { SyncService } from './sync.service';

@Controller('sync')
export class SyncController {
  constructor(
    private readonly sync: SyncService,
    private readonly workspaces: WorkspacesService,
  ) {}

  @Get('bootstrap')
  async bootstrap(
    @CurrentUser() user: AuthUser,
    @Query(new ZodValidationPipe(BootstrapQuerySchema)) q: BootstrapQuery,
  ): Promise<BootstrapResponse> {
    await this.workspaces.assertMember(q.workspaceId, user.userId);
    return this.sync.bootstrap(q.workspaceId);
  }

  @Get('delta')
  async delta(
    @CurrentUser() user: AuthUser,
    @Query(new ZodValidationPipe(DeltaQuerySchema)) q: DeltaQuery,
  ): Promise<DeltaResponse> {
    await this.workspaces.assertMember(q.workspaceId, user.userId);
    return this.sync.delta(q.workspaceId, q.since);
  }
}
