import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "YouTube-style Video Platform",
  description: "YouTube 風アーキテクチャを再現する学習用動画プラットフォーム",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ja" className="h-full antialiased">
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
