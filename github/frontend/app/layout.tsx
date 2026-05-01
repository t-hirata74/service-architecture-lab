import type { Metadata } from "next";
import Link from "next/link";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import UrqlProvider from "@/components/UrqlProvider";
import ViewerSwitcher from "@/components/ViewerSwitcher";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export const metadata: Metadata = {
  title: "github (lab)",
  description: "Service Architecture Lab — github 風 Issue Tracker",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ja" className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}>
      <body className="min-h-full flex flex-col bg-zinc-50 text-zinc-900">
        <UrqlProvider>
          <header className="border-b bg-white">
            <div className="max-w-5xl mx-auto px-6 py-3 flex items-center justify-between gap-4">
              <Link href="/" className="font-semibold text-lg">github (lab)</Link>
              <ViewerSwitcher />
            </div>
          </header>
          <main className="flex-1 max-w-5xl w-full mx-auto px-6 py-6">{children}</main>
        </UrqlProvider>
      </body>
    </html>
  );
}
