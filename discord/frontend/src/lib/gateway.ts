// WebSocket client for Go gateway. Implements the protocol defined in
// discord/docs/adr/0003-presence-heartbeat.md and architecture.md.
//
// Lifecycle:
//   1. open ws ?token=<jwt>
//   2. wait for op:10 HELLO -> learn heartbeat_interval (ms)
//   3. send op:2 IDENTIFY {token, guild_id}
//   4. handle op:0 DISPATCH (READY / MESSAGE_CREATE / PRESENCE_UPDATE / INVALID_SESSION)
//   5. send op:1 HEARTBEAT every interval; expect op:11 ACK
//   6. on close, retry with exponential backoff (capped)

import { WS_BASE } from "./api";

export const OP = {
  Dispatch: 0,
  Heartbeat: 1,
  Identify: 2,
  Hello: 10,
  HeartbeatAck: 11,
} as const;

type Frame<D = unknown> = { op: number; t?: string; d?: D };

export type ReadyPayload = {
  user: { id: number; username: string };
  guild: { id: number; name: string };
  channels: { id: number; name: string }[];
  presences: { user_id: number; username: string }[];
};

export type MessageCreatePayload = {
  id: number;
  channel_id: number;
  guild_id: number;
  user_id: number;
  author_username: string;
  body: string;
  created_at: string;
};

export type PresencePayload = {
  user_id: number;
  username: string;
  status: "online" | "offline";
};

export type GatewayHandlers = {
  onReady?: (d: ReadyPayload) => void;
  onMessageCreate?: (d: MessageCreatePayload) => void;
  onPresenceUpdate?: (d: PresencePayload) => void;
  onInvalidSession?: (reason: string) => void;
  onConnectionState?: (state: "connecting" | "open" | "closed") => void;
};

export class GatewayClient {
  private token: string;
  private guildId: number;
  private handlers: GatewayHandlers;

  private ws: WebSocket | null = null;
  private hbTimer: ReturnType<typeof setInterval> | null = null;
  private retry = 0;
  private closed = false;

  constructor(token: string, guildId: number, handlers: GatewayHandlers) {
    this.token = token;
    this.guildId = guildId;
    this.handlers = handlers;
  }

  connect(): void {
    if (this.closed) return;
    this.handlers.onConnectionState?.("connecting");
    const url = `${WS_BASE}?token=${encodeURIComponent(this.token)}`;
    const ws = new WebSocket(url);
    this.ws = ws;

    ws.addEventListener("open", () => {
      this.handlers.onConnectionState?.("open");
      this.retry = 0;
    });

    ws.addEventListener("message", (ev) => this.onFrame(ev.data));

    ws.addEventListener("close", () => {
      this.clearHeartbeat();
      this.handlers.onConnectionState?.("closed");
      if (!this.closed) this.scheduleReconnect();
    });

    ws.addEventListener("error", () => {
      // close handler will run after; nothing extra to do
    });
  }

  close(): void {
    this.closed = true;
    this.clearHeartbeat();
    this.ws?.close();
    this.ws = null;
  }

  private onFrame(raw: unknown): void {
    if (typeof raw !== "string") return;
    let frame: Frame;
    try {
      frame = JSON.parse(raw);
    } catch {
      return;
    }
    switch (frame.op) {
      case OP.Hello: {
        const d = frame.d as { heartbeat_interval: number } | undefined;
        const interval = d?.heartbeat_interval ?? 10000;
        this.identify();
        this.startHeartbeat(interval);
        break;
      }
      case OP.HeartbeatAck:
        // could record latency here
        break;
      case OP.Dispatch: {
        const t = frame.t ?? "";
        if (t === "READY") {
          this.handlers.onReady?.(frame.d as ReadyPayload);
        } else if (t === "MESSAGE_CREATE") {
          this.handlers.onMessageCreate?.(frame.d as MessageCreatePayload);
        } else if (t === "PRESENCE_UPDATE") {
          this.handlers.onPresenceUpdate?.(frame.d as PresencePayload);
        } else if (t === "INVALID_SESSION") {
          const d = frame.d as { reason?: string } | undefined;
          this.handlers.onInvalidSession?.(d?.reason ?? "invalid session");
          this.close();
        }
        break;
      }
    }
  }

  private identify(): void {
    this.send({
      op: OP.Identify,
      d: { token: this.token, guild_id: this.guildId },
    });
  }

  private startHeartbeat(intervalMs: number): void {
    this.clearHeartbeat();
    // Send first heartbeat after one full interval; before that the server
    // already saw IDENTIFY which sets initial lastHB on the server side.
    this.hbTimer = setInterval(() => {
      this.send({ op: OP.Heartbeat });
    }, intervalMs);
  }

  private clearHeartbeat(): void {
    if (this.hbTimer) {
      clearInterval(this.hbTimer);
      this.hbTimer = null;
    }
  }

  private send(frame: Frame): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(frame));
    }
  }

  private scheduleReconnect(): void {
    this.retry++;
    const delay = Math.min(15000, 500 * 2 ** Math.min(this.retry, 5));
    setTimeout(() => {
      if (!this.closed) this.connect();
    }, delay);
  }
}
