import { NestFactory } from '@nestjs/core';
import { WsAdapter } from '@nestjs/platform-ws';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  // frontend (:3145) からのアクセス用。ローカル完結なので origin は緩くて良い
  app.enableCors({ origin: true });
  // 素の WebSocket (socket.io は使わない / ADR 0005)
  app.useWebSocketAdapter(new WsAdapter(app));
  await app.listen(process.env.PORT ?? 3140);
}
void bootstrap();
