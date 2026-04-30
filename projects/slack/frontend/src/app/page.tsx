"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { getToken } from "@/lib/api";

export default function Home() {
  const router = useRouter();

  useEffect(() => {
    const token = getToken();
    router.replace(token ? "/me" : "/login");
  }, [router]);

  return (
    <div className="flex flex-1 items-center justify-center text-sm text-slate-500">
      Loading…
    </div>
  );
}
