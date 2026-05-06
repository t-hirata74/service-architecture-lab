"use client";

import { useRouter } from "next/navigation";
import { use, useEffect, useState } from "react";
import { addToCart, getProduct, type ApiProduct } from "@/lib/api";
import { useShop } from "@/lib/shop";
import { useAuth } from "@/lib/auth";

export default function ProductPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = use(params);
  const [shop] = useShop();
  const { token } = useAuth(shop);
  const router = useRouter();
  const [product, setProduct] = useState<ApiProduct | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [flash, setFlash] = useState<string | null>(null);

  useEffect(() => {
    setError(null);
    getProduct(shop, slug)
      .then(setProduct)
      .catch((e) => setError(e instanceof Error ? e.message : String(e)));
  }, [shop, slug]);

  async function onAdd(variantId: number) {
    if (!token) {
      router.push(`/login?next=/products/${slug}`);
      return;
    }
    setBusy(true);
    setFlash(null);
    try {
      await addToCart(shop, variantId, 1);
      setFlash("added to cart");
    } catch (e) {
      setFlash(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  if (error) return <div className="text-sm text-red-700 bg-red-50 border border-red-200 rounded px-3 py-2">{error}</div>;
  if (!product) return <div className="text-sm text-zinc-500">loading…</div>;

  return (
    <div className="space-y-5" data-testid={`product-detail-${product.slug}`}>
      <div>
        <p className="text-xs text-zinc-500 font-mono">/{product.slug}</p>
        <h2 className="text-2xl font-bold tracking-tight" data-testid="product-title">{product.title}</h2>
      </div>
      {product.description && <p className="text-sm text-zinc-600">{product.description}</p>}

      <ul className="bg-white border border-zinc-200 rounded-lg divide-y divide-zinc-200">
        {(product.variants ?? []).map((v) => (
          <li key={v.id} className="px-4 py-3 flex items-center gap-3">
            <div className="flex-1">
              <div className="text-sm font-mono text-zinc-700">{v.sku}</div>
              <div className="text-xs text-zinc-500">{v.currency} {v.price_cents.toLocaleString()}</div>
            </div>
            <button
              disabled={busy}
              onClick={() => onAdd(v.id)}
              data-testid={`add-${v.sku}`}
              className="text-sm bg-zinc-900 text-white px-3 py-1.5 rounded hover:bg-zinc-700 disabled:opacity-50"
            >
              + cart
            </button>
          </li>
        ))}
      </ul>

      {flash && <div className="text-xs text-zinc-600" data-testid="flash">{flash}</div>}
    </div>
  );
}
