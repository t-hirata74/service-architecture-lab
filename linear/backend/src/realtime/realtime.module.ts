import { Module } from '@nestjs/common';
import { SyncModule } from '../sync/sync.module';
import { WorkspacesModule } from '../workspaces/workspaces.module';
import { RealtimeService } from './realtime.service';
import { SyncGateway } from './sync.gateway';

@Module({
  imports: [SyncModule, WorkspacesModule],
  providers: [RealtimeService, SyncGateway],
  exports: [RealtimeService],
})
export class RealtimeModule {}
