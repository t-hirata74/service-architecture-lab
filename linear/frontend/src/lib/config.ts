export const API_URL =
  process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:3140';

export const WS_URL = API_URL.replace(/^http/, 'ws');
