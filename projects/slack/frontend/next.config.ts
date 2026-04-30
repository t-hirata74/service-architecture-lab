import type { NextConfig } from "next";
import path from "node:path";

const nextConfig: NextConfig = {
  // Next 16: 上位ディレクトリの lockfile を誤検出しないよう明示
  turbopack: {
    root: path.resolve(__dirname),
  },
};

export default nextConfig;
