import { createConsumer, type Consumer } from "@rails/actioncable";
import { getToken } from "./api";

const CABLE_URL = process.env.NEXT_PUBLIC_CABLE_URL ?? "ws://localhost:3010/cable";

let consumer: Consumer | null = null;

export function getCableConsumer(): Consumer {
  if (consumer) return consumer;
  const token = getToken();
  if (!token) throw new Error("JWT が無いため Cable 接続不可");
  consumer = createConsumer(`${CABLE_URL}?token=${encodeURIComponent(token)}`);
  return consumer;
}

export function disconnectCable(): void {
  consumer?.disconnect();
  consumer = null;
}
