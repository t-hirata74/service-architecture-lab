// WebSocket client for the driver gateway (backend internal/ws/protocol.go)。
//
// rider 側に WS push は無い (rider は REST poll)。この client は driver 専用。
//
// Lifecycle:
//   1. open ws ?token=<jwt>  (driver role 以外は backend が 403 で弾く)
//   2. server → "hello" {user_id, role} を受信
//   3. client → "go_online" {lat, lng} を送って idle 化 + matcher 登録
//   4. server → "offer" {trip_id, pickup/dropoff, expires_at} を受信
//   5. client → "accept" | "reject" {trip_id}
//   server の ping frame はブラウザが自動 pong するのでアプリ層 heartbeat は不要。

import { WS_BASE } from "./api";

export type Outbound =
  | { op: "go_online"; lat: number; lng: number }
  | { op: "position"; lat: number; lng: number }
  | { op: "accept"; trip_id: number }
  | { op: "reject"; trip_id: number }
  | { op: "go_offline" };

export type HelloMsg = { op: "hello"; user_id: number; role: string };
export type OfferMsg = {
  op: "offer";
  trip_id: number;
  pickup_lat: number;
  pickup_lng: number;
  dropoff_lat: number;
  dropoff_lng: number;
  expires_at: string;
};
export type ErrorMsg = { op: "error"; message: string };
export type Inbound = HelloMsg | OfferMsg | ErrorMsg;

export type ConnState = "connecting" | "open" | "closed";

export type DriverHandlers = {
  onHello?: (m: HelloMsg) => void;
  onOffer?: (m: OfferMsg) => void;
  onError?: (m: ErrorMsg) => void;
  onState?: (s: ConnState) => void;
};

export class DriverGateway {
  private token: string;
  private handlers: DriverHandlers;
  private ws: WebSocket | null = null;
  private closed = false;

  constructor(token: string, handlers: DriverHandlers) {
    this.token = token;
    this.handlers = handlers;
  }

  connect(): void {
    if (this.closed) return;
    this.handlers.onState?.("connecting");
    const url = `${WS_BASE}?token=${encodeURIComponent(this.token)}`;
    const ws = new WebSocket(url);
    this.ws = ws;

    ws.addEventListener("open", () => this.handlers.onState?.("open"));
    ws.addEventListener("message", (ev) => this.onFrame(ev.data));
    ws.addEventListener("close", () => this.handlers.onState?.("closed"));
    ws.addEventListener("error", () => {
      // close handler が後続するので追加処理は不要
    });
  }

  close(): void {
    this.closed = true;
    this.ws?.close();
    this.ws = null;
  }

  goOnline(lat: number, lng: number): void {
    this.send({ op: "go_online", lat, lng });
  }

  accept(tripId: number): void {
    this.send({ op: "accept", trip_id: tripId });
  }

  reject(tripId: number): void {
    this.send({ op: "reject", trip_id: tripId });
  }

  goOffline(): void {
    this.send({ op: "go_offline" });
  }

  private onFrame(raw: unknown): void {
    if (typeof raw !== "string") return;
    let msg: Inbound;
    try {
      msg = JSON.parse(raw) as Inbound;
    } catch {
      return;
    }
    switch (msg.op) {
      case "hello":
        this.handlers.onHello?.(msg);
        break;
      case "offer":
        this.handlers.onOffer?.(msg);
        break;
      case "error":
        this.handlers.onError?.(msg);
        break;
    }
  }

  private send(frame: Outbound): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(frame));
    }
  }
}
