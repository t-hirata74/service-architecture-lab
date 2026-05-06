"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { listProducts, type ApiProduct } from "@/lib/api";
import { useShop, SHOPS } from "@/lib/shop";

export default function HomePage() {
  const [shop] = useShop();
  const [products, setProducts] = useState<ApiProduct[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    setLoading(true);
    setError(null);
    listProducts(shop)
      .then((p) => { setProducts(p); setLoading(false); })
      .catch((e) => { setError(e instanceof Error ? e.message : String(e)); setLoading(false); });
  }, [shop]);

  const shopName = SHOPS.find((s) => s.subdomain === shop)?.name ?? shop;

  return (
    <div className="space-y-5">
      <header className="space-y-1">
        <h2 className="text-2xl font-bold tracking-tight">{shopName}</h2>
        <p className="text-sm text-zinc-500">
          tenant <span className="font-mono text-zinc-700">{shop}</span> の公開 product (storefront API: <code className="text-xs">GET /storefront/products</code>)
        </p>
      </header>

      {error && (
        <div className="text-sm text-red-700 bg-red-50 border border-red-200 rounded px-3 py-2">{error}</div>
      )}

      <ul className="grid gap-3 sm:grid-cols-2" data-testid="product-list">
        {products.map((p) => (
          <li key={p.id}>
            <Link
              href={`/products/${p.slug}`}
              className="block bg-white border border-zinc-200 rounded-lg p-4 hover:border-zinc-400 transition-colors"
              data-testid={`product-${p.slug}`}
            >
              <div className="flex items-baseline gap-2">
                <span className="font-semibold text-zinc-900">{p.title}</span>
                <span className="text-xs text-zinc-400 font-mono">/{p.slug}</span>
              </div>
              {p.description && <p className="text-sm text-zinc-500 mt-1">{p.description}</p>}
            </Link>
          </li>
        ))}
        {!loading && products.length === 0 && !error && (
          <li className="bg-white border border-zinc-200 rounded-lg px-4 py-12 text-center text-sm text-zinc-500 sm:col-span-2">
            no products yet
          </li>
        )}
      </ul>
    </div>
  );
}
