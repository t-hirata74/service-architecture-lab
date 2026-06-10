import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  // frontend (:3145) からのアクセス用。ローカル完結なので origin は緩くて良い
  app.enableCors({ origin: true });
  await app.listen(process.env.PORT ?? 3140);
}
void bootstrap();
