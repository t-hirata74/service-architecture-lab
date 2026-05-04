"use client";

import { useEffect, useState } from "react";
import { listProducts, type ApiProduct } from "@/lib/api";

export default function HomePage() {
  const [products, setProducts] = useState<ApiProduct[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    listProducts()
      .then(setProducts)
      .catch((e) => setError(e instanceof Error ? e.message : String(e)));
  }, []);

  return (
    <div className="space-y-6">
      <header className="space-y-1">
        <h1 className="text-3xl font-bold tracking-tight">products</h1>
        <p className="text-sm text-zinc-500">
          現在のテナントで公開されている product 一覧 (storefront API)
        </p>
      </header>

      {error && (
        <div className="text-sm text-red-700 bg-red-50 border border-red-200 rounded px-3 py-2">
          {error}
        </div>
      )}

      <ul className="bg-white border border-zinc-200 rounded-lg shadow-sm divide-y divide-zinc-200 overflow-hidden">
        {products.map((p) => (
          <li key={p.id} className="px-4 py-3">
            <div className="flex items-baseline gap-2">
              <span className="font-semibold text-zinc-900">{p.title}</span>
              <span className="text-xs text-zinc-400">/{p.slug}</span>
            </div>
            {p.description && (
              <p className="text-sm text-zinc-500 mt-1">{p.description}</p>
            )}
          </li>
        ))}
        {products.length === 0 && !error && (
          <li className="px-4 py-12 text-center text-sm text-zinc-500">
            no products yet
          </li>
        )}
      </ul>
    </div>
  );
}
