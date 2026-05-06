import type { Metadata } from "next";
import "./globals.css";
import { Header } from "@/components/Header";

export const metadata: Metadata = {
  title: "Zoom (lab)",
  description: "Zoom-style meeting platform lab — lifecycle state machine / dynamic host transfer / recording → summary pipeline",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ja" className="h-full antialiased">
      <body className="min-h-full flex flex-col bg-zinc-50">
        <Header />
        <main className="flex-1 max-w-5xl mx-auto w-full px-4 py-6">{children}</main>
      </body>
    </html>
  );
}
