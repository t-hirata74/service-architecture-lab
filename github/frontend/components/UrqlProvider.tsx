"use client";

import { Provider } from "urql";
import { getClient } from "@/lib/urqlClient";

export default function UrqlProvider({ children }: { children: React.ReactNode }) {
  return <Provider value={getClient()}>{children}</Provider>;
}
