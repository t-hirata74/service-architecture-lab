import { BadRequestException } from '@nestjs/common';
import { z } from 'zod';
import { ZodValidationPipe } from './zod-validation.pipe';

describe('ZodValidationPipe', () => {
  const schema = z.object({ name: z.string().min(1) });
  const pipe = new ZodValidationPipe(schema);

  it('スキーマ適合時は parse 済みの値を返す', () => {
    expect(pipe.transform({ name: 'a', extra: 1 })).toEqual({ name: 'a' });
  });

  it('不適合時は 400 (issues の path/code 付き)', () => {
    try {
      pipe.transform({ name: '' });
      fail('should throw');
    } catch (e) {
      expect(e).toBeInstanceOf(BadRequestException);
      const body = (e as BadRequestException).getResponse() as {
        issues: Array<{ path: string }>;
      };
      expect(body.issues[0].path).toBe('name');
    }
  });
});
