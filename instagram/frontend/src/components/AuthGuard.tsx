"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useHasMounted, useStoredToken } from "@/lib/hooks";

/** localStorage の token を確認し、無ければ /login に redirect する。
 * SSR では何もせず (useHasMounted=false)、hydration 後に判定する。
 */
export function AuthGuard({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const mounted = useHasMounted();
  const token = useStoredToken();

  useEffect(() => {
    if (mounted && !token) {
      router.replace("/login");
    }
  }, [mounted, token, router]);

  if (!mounted || !token) {
    return <p className="text-sm text-black/50 dark:text-white/50">loading...</p>;
  }
  return <>{children}</>;
}
