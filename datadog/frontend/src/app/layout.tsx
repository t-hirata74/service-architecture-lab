import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "datadog-lab",
  description: "高基数メトリクス ingestion + 固定窓 rollup + alert rule engine (学習用)",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ja">
      <body>{children}</body>
    </html>
  );
}
