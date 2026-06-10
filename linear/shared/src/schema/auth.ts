import { z } from 'zod';

export const SignupRequestSchema = z.object({
  email: z.string().email().max(255),
  password: z.string().min(8).max(72),
  name: z.string().min(1).max(100),
});
export type SignupRequest = z.infer<typeof SignupRequestSchema>;

export const LoginRequestSchema = z.object({
  email: z.string().email().max(255),
  password: z.string().min(1).max(72),
});
export type LoginRequest = z.infer<typeof LoginRequestSchema>;
