import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'linear — sync engine lab',
  description:
    'Linear 風 issue tracker (server 権威 sync log + optimistic/offline client)',
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ja">
      <body className="bg-zinc-50 text-zinc-900 antialiased">{children}</body>
    </html>
  );
}
