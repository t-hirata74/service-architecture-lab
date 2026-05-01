"use client";

import { useState } from "react";
import { Provider, Client, cacheExchange, fetchExchange } from "urql";
import { getViewerLogin } from "@/lib/viewer";

const GRAPHQL_URL = process.env.NEXT_PUBLIC_GRAPHQL_URL ?? "http://127.0.0.1:3030/graphql";

function createClient(): Client {
  return new Client({
    url: GRAPHQL_URL,
    exchanges: [cacheExchange, fetchExchange],
    fetchOptions: () => {
      const login = typeof window !== "undefined" ? getViewerLogin() : null;
      const headers: Record<string, string> = { "Content-Type": "application/json" };
      if (login) headers["X-User-Login"] = login;
      return { headers };
    },
    requestPolicy: "cache-and-network"
  });
}

// useState の initializer で Client を 1 度だけ生成 (SSR と CSR で別インスタンス)。
// urql は useQuery の dispatch のみ行い、fetch は Suspense / awaited 経路でない限り
// SSR 中には実行されない。
export default function UrqlProvider({ children }: { children: React.ReactNode }) {
  const [client] = useState<Client>(() => createClient());
  return <Provider value={client}>{children}</Provider>;
}
