import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// dev は frontend:3155 / backend:3150。同一オリジンで RPC を叩くため backend へ proxy する。
export default defineConfig({
  plugins: [react()],
  server: {
    port: 3155,
    proxy: {
      '/accounts': 'http://localhost:3150',
      '/health': 'http://localhost:3150',
    },
  },
});
