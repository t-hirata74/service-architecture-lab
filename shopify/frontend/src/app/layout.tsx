import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Shopify (lab)",
  description: "Shopify-style EC platform lab — modular monolith / multi-tenancy / inventory",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ja" className="h-full antialiased">
      <body className="min-h-full flex flex-col">
        <header className="border-b border-zinc-200 bg-white">
          <div className="max-w-5xl mx-auto px-4 py-3 flex items-center justify-between">
            <h1 className="font-semibold tracking-tight text-zinc-900">shopify-lab</h1>
            <span className="text-xs text-zinc-500">storefront</span>
          </div>
        </header>
        <main className="flex-1 max-w-5xl mx-auto w-full px-4 py-6">{children}</main>
      </body>
    </html>
  );
}
