import type { Metadata } from "next";
import "./globals.css";
import { NavBar } from "@/components/NavBar";

export const metadata: Metadata = {
  title: "Instagram (lab)",
  description: "Instagram-style timeline lab project",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ja" className="h-full antialiased">
      <body className="min-h-full flex flex-col">
        <NavBar />
        <main className="flex-1 max-w-2xl mx-auto w-full px-4 py-6">
          {children}
        </main>
      </body>
    </html>
  );
}
