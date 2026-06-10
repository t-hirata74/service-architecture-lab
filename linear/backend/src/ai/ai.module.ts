import { Module } from '@nestjs/common';
import { WorkspacesModule } from '../workspaces/workspaces.module';
import { AiController } from './ai.controller';
import { AiService } from './ai.service';

@Module({
  imports: [WorkspacesModule],
  controllers: [AiController],
  providers: [AiService],
})
export class AiModule {}
