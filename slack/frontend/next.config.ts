import type { NextConfig } from "next";
import path from "node:path";

const nextConfig: NextConfig = {
  // ActionCable の二重 subscribe を避けるため StrictMode の effect 二重起動を無効化
  reactStrictMode: false,
  // Next 16: 上位ディレクトリの lockfile を誤検出しないよう明示
  turbopack: {
    root: path.resolve(__dirname),
  },
};

export default nextConfig;
