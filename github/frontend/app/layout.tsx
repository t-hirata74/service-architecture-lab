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
      <body className="min-h-full flex flex-col bg-[var(--bg)] text-[var(--fg)]">
        <UrqlProvider>
          <header className="sticky top-0 z-10 border-b border-[var(--border)] bg-[var(--bg-elevated)]/95 backdrop-blur">
            <div className="max-w-5xl mx-auto px-6 h-14 flex items-center justify-between gap-4">
              <Link
                href="/"
                className="flex items-center gap-2 font-semibold text-base hover:opacity-90 transition-opacity"
              >
                <span
                  aria-hidden
                  className="size-7 rounded-md bg-[var(--fg)] grid place-items-center text-[var(--bg-elevated)] text-base"
                >
                  ⌥
                </span>
                <span>github (lab)</span>
              </Link>
              <ViewerSwitcher />
            </div>
          </header>
          <main className="flex-1 max-w-5xl w-full mx-auto px-6 py-6">{children}</main>
        </UrqlProvider>
      </body>
    </html>
  );
}
