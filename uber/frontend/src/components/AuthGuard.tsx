"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { getStoredUser, type ApiUser, type Role } from "@/lib/api";

// requiredRole を渡すと、role 不一致のユーザを自分の役割ページへ送り返す。
// rider が /driver を開く (WS が backend で 403 になる) ような無駄足を防ぐ。
export function AuthGuard({
  children,
  requiredRole,
}: {
  children: (user: ApiUser) => React.ReactNode;
  requiredRole?: Role;
}) {
  const router = useRouter();
  const [user, setUser] = useState<ApiUser | null>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const u = getStoredUser();
    if (!u) {
      router.replace("/login");
      return;
    }
    if (requiredRole && u.role !== requiredRole) {
      router.replace(u.role === "driver" ? "/driver" : "/rider");
      return;
    }
    setUser(u);
    setReady(true);
  }, [router, requiredRole]);

  if (!ready || !user) return null;
  return <>{children(user)}</>;
}
