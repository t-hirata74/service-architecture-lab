import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { PrismaClient } from '@prisma/client';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from '../src/app.module';

export async function createTestApp(): Promise<INestApplication<App>> {
  const moduleRef = await Test.createTestingModule({
    imports: [AppModule],
  }).compile();
  const app = moduleRef.createNestApplication();
  await app.init();
  return app;
}

/** FK 依存の子 → 親の順で全削除 (e2e は --runInBand 前提で DB を共有する) */
export async function resetDb(prisma: PrismaClient): Promise<void> {
  await prisma.syncOp.deleteMany();
  await prisma.mutationLedger.deleteMany();
  await prisma.comment.deleteMany();
  await prisma.issueLabel.deleteMany();
  await prisma.issue.deleteMany();
  await prisma.label.deleteMany();
  await prisma.workflowState.deleteMany();
  await prisma.team.deleteMany();
  await prisma.workspaceMember.deleteMany();
  await prisma.workspace.deleteMany();
  await prisma.user.deleteMany();
}

export interface TestActor {
  token: string;
  userId: number;
  workspaceId: number;
}

export async function signupActor(
  app: INestApplication<App>,
  email: string,
  name = 'Test User',
): Promise<TestActor> {
  const res = await request(app.getHttpServer())
    .post('/auth/signup')
    .send({ email, password: 'password123', name })
    .expect(201);
  const body = res.body as {
    token: string;
    user: { id: number };
    workspace: { id: number };
  };
  return {
    token: body.token,
    userId: body.user.id,
    workspaceId: body.workspace.id,
  };
}
