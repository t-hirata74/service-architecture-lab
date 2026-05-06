"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { SHOPS, useShop } from "@/lib/shop";
import { clearToken, useAuth } from "@/lib/auth";

export function Header() {
  const [shop, setShop] = useShop();
  const { email } = useAuth(shop);
  const router = useRouter();
  const pathname = usePathname();

  // SSR と client-render を一致させる: localStorage 由来の表示は mount 後のみ。
  // (mount 前は静的な placeholder を返すので gif でも余計な flicker が出ない)
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  return (
    <header className="border-b border-zinc-200 bg-white sticky top-0 z-10">
      <div className="max-w-5xl mx-auto px-4 py-3 flex items-center gap-4">
        <Link href="/" className="font-semibold tracking-tight text-zinc-900">
          shopify-lab
        </Link>

        <nav className="flex items-center gap-3 text-sm">
          <Link href="/" data-active={pathname === "/"} className="text-zinc-600 data-[active=true]:text-zinc-900 data-[active=true]:font-medium">
            store
          </Link>
          <Link href="/cart" data-active={pathname === "/cart"} className="text-zinc-600 data-[active=true]:text-zinc-900 data-[active=true]:font-medium">
            cart
          </Link>
          <Link href="/admin/system" data-active={pathname?.startsWith("/admin")} className="text-zinc-600 data-[active=true]:text-zinc-900 data-[active=true]:font-medium">
            system
          </Link>
        </nav>

        <div className="flex-1" />

        {mounted ? (
          <>
            <label className="flex items-center gap-2 text-xs text-zinc-500" data-testid="shop-switcher">
              <span>tenant:</span>
              <select
                value={shop}
                onChange={(e) => {
                  setShop(e.target.value as (typeof SHOPS)[number]["subdomain"]);
                  router.refresh();
                }}
                className="border border-zinc-300 rounded px-2 py-1 text-xs bg-white text-zinc-900"
              >
                {SHOPS.map((s) => (
                  <option key={s.subdomain} value={s.subdomain}>
                    {s.name} ({s.subdomain})
                  </option>
                ))}
              </select>
            </label>

            {email ? (
              <div className="flex items-center gap-2 text-xs">
                <span className="text-zinc-500" data-testid="auth-email">@{email}</span>
                <button
                  onClick={() => {
                    clearToken(shop);
                    router.refresh();
                  }}
                  className="text-zinc-500 hover:text-zinc-900"
                >
                  logout
                </button>
              </div>
            ) : (
              <Link href="/login" className="text-xs text-zinc-600 hover:text-zinc-900">
                login
              </Link>
            )}
          </>
        ) : (
          // mount 前 placeholder (高さを揃えてレイアウトが揺れないようにする)
          <div className="h-6" />
        )}
      </div>
    </header>
  );
}
