import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "figma-lab",
  description: "Server 権威 LWW-CRDT による図形キャンバスのリアルタイム共同編集 (学習用)",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ja">
      <body>{children}</body>
    </html>
  );
}
