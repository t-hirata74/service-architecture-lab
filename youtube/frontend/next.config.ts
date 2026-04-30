import type { NextConfig } from "next";
import path from "node:path";

const nextConfig: NextConfig = {
  // Next 16: 上位 lockfile を誤検出させないため明示
  turbopack: {
    root: path.resolve(__dirname),
  },
};

export default nextConfig;
