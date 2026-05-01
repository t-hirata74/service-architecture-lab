"use client";

import { Client, cacheExchange, fetchExchange } from "urql";
import { getViewerLogin } from "./viewer";

const GRAPHQL_URL = process.env.NEXT_PUBLIC_GRAPHQL_URL ?? "http://localhost:3030/graphql";

let _client: Client | null = null;

export function getClient(): Client {
  if (_client) return _client;

  _client = new Client({
    url: GRAPHQL_URL,
    exchanges: [cacheExchange, fetchExchange],
    fetchOptions: () => {
      const login = getViewerLogin();
      const headers: Record<string, string> = { "Content-Type": "application/json" };
      if (login) headers["X-User-Login"] = login;
      return { headers };
    },
    requestPolicy: "cache-and-network"
  });
  return _client;
}
