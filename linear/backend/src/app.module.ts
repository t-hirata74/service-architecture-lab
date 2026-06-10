import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { AppController } from './app.controller';
import { AuthModule } from './auth/auth.module';
import { JwtAuthGuard } from './auth/jwt-auth.guard';
import { IssuesModule } from './issues/issues.module';
import { MutationsModule } from './mutations/mutations.module';
import { PrismaModule } from './prisma/prisma.module';
import { SyncModule } from './sync/sync.module';
import { TeamsModule } from './teams/teams.module';
import { WorkspacesModule } from './workspaces/workspaces.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    PrismaModule,
    AuthModule,
    WorkspacesModule,
    SyncModule,
    TeamsModule,
    IssuesModule,
    MutationsModule,
  ],
  controllers: [AppController],
  providers: [
    // 認証はデフォルト必須。公開 endpoint は @Public() で明示する
    { provide: APP_GUARD, useClass: JwtAuthGuard },
  ],
})
export class AppModule {}
