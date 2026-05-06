"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { checkout, getCart, removeFromCart, type ApiCart, type ApiOrder } from "@/lib/api";
import { useShop } from "@/lib/shop";
import { useAuth } from "@/lib/auth";

export default function CartPage() {
  const [shop] = useShop();
  const { token } = useAuth(shop);
  const router = useRouter();
  const [cart, setCart] = useState<ApiCart | null>(null);
  const [order, setOrder] = useState<ApiOrder | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!token) {
      router.push("/login?next=/cart");
      return;
    }
    setError(null);
    getCart(shop)
      .then(setCart)
      .catch((e) => setError(e instanceof Error ? e.message : String(e)));
  }, [shop, token, router]);

  async function onCheckout() {
    setBusy(true);
    setError(null);
    setOrder(null);
    try {
      const r = await checkout(shop);
      if (r.ok) {
        setOrder(r.order);
        setCart({ id: 0, status: "completed", items: [] });
      } else {
        setError(r.error === "insufficient_stock" ? "在庫不足: 別の購入者が先に確保しました (ADR 0003)" : r.error);
      }
    } finally {
      setBusy(false);
    }
  }

  if (!token) return null;

  return (
    <div className="space-y-5">
      <h2 className="text-2xl font-bold tracking-tight">cart</h2>

      {!cart ? (
        <div className="text-sm text-zinc-500">loading…</div>
      ) : cart.items.length === 0 && !order ? (
        <div className="text-sm text-zinc-500 bg-white border border-zinc-200 rounded p-6 text-center">
          cart is empty
        </div>
      ) : (
        <ul className="bg-white border border-zinc-200 rounded-lg divide-y divide-zinc-200" data-testid="cart-items">
          {cart.items.map((it) => (
            <li key={it.variant_id} className="px-4 py-3 flex items-center gap-3">
              <div className="flex-1">
                <div className="text-sm font-mono">{it.sku}</div>
                <div className="text-xs text-zinc-500">{it.currency} {it.price_cents.toLocaleString()} × {it.quantity}</div>
              </div>
              <button
                onClick={() => removeFromCart(shop, it.variant_id).then(setCart)}
                className="text-xs text-zinc-500 hover:text-red-600"
              >
                remove
              </button>
            </li>
          ))}
        </ul>
      )}

      {cart && cart.items.length > 0 && (
        <button
          onClick={onCheckout}
          disabled={busy}
          data-testid="checkout-button"
          className="bg-zinc-900 text-white px-4 py-2 rounded font-medium hover:bg-zinc-700 disabled:opacity-50"
        >
          {busy ? "checking out…" : "checkout"}
        </button>
      )}

      {error && (
        <div className="text-sm text-red-700 bg-red-50 border border-red-200 rounded px-3 py-2" data-testid="checkout-error">
          {error}
        </div>
      )}

      {order && (
        <div className="bg-emerald-50 border border-emerald-200 rounded p-4 space-y-1" data-testid="order-confirmation">
          <div className="text-sm font-semibold text-emerald-900">order #{order.number} created</div>
          <div className="text-xs text-emerald-800 font-mono">
            total = {order.currency} {order.total_cents.toLocaleString()} / status = {order.status}
          </div>
          <div className="text-xs text-emerald-700">
            ADR 0004: webhook が mock receiver (:4000) に配信されます
          </div>
        </div>
      )}
    </div>
  );
}
