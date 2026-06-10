import { INestApplication } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';
import request from 'supertest';
import { App } from 'supertest/types';
import { createTestApp, resetDb, signupActor } from './helpers';

describe('auth (e2e)', () => {
  let app: INestApplication<App>;
  const prisma = new PrismaClient();

  beforeAll(async () => {
    app = await createTestApp();
  });

  beforeEach(async () => {
    await resetDb(prisma);
  });

  afterAll(async () => {
    await app.close();
    await prisma.$disconnect();
  });

  it('GET /health は公開', async () => {
    await request(app.getHttpServer()).get('/health').expect(200);
  });

  it('signup は user + workspace + 既定 team/states を seed する', async () => {
    const actor = await signupActor(app, 'alice@example.com', 'Alice');

    const teams = await prisma.team.findMany({
      where: { workspaceId: actor.workspaceId },
      include: { states: true },
    });
    expect(teams).toHaveLength(1);
    expect(teams[0].key).toBe('GEN');
    expect(teams[0].states).toHaveLength(5);

    // signup の seed は sync_ops を発行しない (ADR 0002 / auth.service)
    expect(
      await prisma.syncOp.count({ where: { workspaceId: actor.workspaceId } }),
    ).toBe(0);
  });

  it('email 重複の signup は 409', async () => {
    await signupActor(app, 'alice@example.com');
    await request(app.getHttpServer())
      .post('/auth/signup')
      .send({ email: 'alice@example.com', password: 'password123', name: 'B' })
      .expect(409);
  });

  it('login: 正しい資格情報で 200 / 誤りで 401', async () => {
    await signupActor(app, 'alice@example.com');
    await request(app.getHttpServer())
      .post('/auth/login')
      .send({ email: 'alice@example.com', password: 'password123' })
      .expect(200);
    await request(app.getHttpServer())
      .post('/auth/login')
      .send({ email: 'alice@example.com', password: 'wrong-password' })
      .expect(401);
  });

  it('GET /auth/me は自分の workspace 一覧を返す / token 無しは 401', async () => {
    const actor = await signupActor(app, 'alice@example.com');
    const res = await request(app.getHttpServer())
      .get('/auth/me')
      .set('Authorization', `Bearer ${actor.token}`)
      .expect(200);
    const body = res.body as { workspaces: Array<{ id: number }> };
    expect(body.workspaces.map((w) => w.id)).toEqual([actor.workspaceId]);

    await request(app.getHttpServer()).get('/auth/me').expect(401);
  });

  it('不正な body の signup は 400 (zod)', async () => {
    await request(app.getHttpServer())
      .post('/auth/signup')
      .send({ email: 'not-an-email', password: 'short', name: '' })
      .expect(400);
  });
});
