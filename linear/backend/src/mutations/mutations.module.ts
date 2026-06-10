import { Module } from '@nestjs/common';
import { IssuesModule } from '../issues/issues.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { SyncModule } from '../sync/sync.module';
import { TeamsModule } from '../teams/teams.module';
import { WorkspacesModule } from '../workspaces/workspaces.module';
import { MutationsController } from './mutations.controller';
import { MutationsService } from './mutations.service';

@Module({
  imports: [
    WorkspacesModule,
    SyncModule,
    TeamsModule,
    IssuesModule,
    RealtimeModule,
  ],
  controllers: [MutationsController],
  providers: [MutationsService],
})
export class MutationsModule {}
