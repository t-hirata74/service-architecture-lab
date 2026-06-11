import { ServerWsMessageSchema } from '@linear/shared';
import type { SyncEngine } from '@linear/client-sync';
import { WS_URL } from './config';

/**
 * 素の WebSocket 購読層 (ADR 0005)。
 * - 接続成功 = online (hello を受けた engine が catch-up → replay する)
 * - 切断 = offline 扱いにして指数 backoff で再接続
 * - ブラウザの online/offline イベントも engine に中継する
 * 配達保証は持たない。順序・復元の正しさはすべて engine 側 (seq 連続性 + delta)。
 */
export class WsClient {
  private ws: WebSocket | null = null;
  private stopped = false;
  private attempt = 0;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;

  constructor(
    private readonly engine: SyncEngine,
    private readonly workspaceId: number,
    private readonly token: string,
  ) {}

  private readonly onBrowserOnline = (): void => {
    this.engine.setOnline(true);
    this.connect();
  };

  private readonly onBrowserOffline = (): void => {
    this.engine.setOnline(false);
  };

  start(): void {
    window.addEventListener('online', this.onBrowserOnline);
    window.addEventListener('offline', this.onBrowserOffline);
    this.engine.setOnline(navigator.onLine);
    this.connect();
  }

  stop(): void {
    this.stopped = true;
    window.removeEventListener('online', this.onBrowserOnline);
    window.removeEventListener('offline', this.onBrowserOffline);
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    this.ws?.close();
  }

  private connect(): void {
    if (this.stopped || this.ws) return;
    const ws = new WebSocket(
      `${WS_URL}/sync/ws?workspaceId=${this.workspaceId}&token=${encodeURIComponent(this.token)}`,
    );
    this.ws = ws;

    ws.onopen = () => {
      this.attempt = 0;
      this.engine.setOnline(true);
    };
    ws.onmessage = (event: MessageEvent<string>) => {
      this.engine.receiveServerMessage(
        ServerWsMessageSchema.parse(JSON.parse(event.data)),
      );
    };
    ws.onclose = () => {
      this.ws = null;
      if (this.stopped) return;
      this.engine.setOnline(false);
      this.scheduleReconnect();
    };
    ws.onerror = () => ws.close();
  }

  private scheduleReconnect(): void {
    const delay = Math.min(500 * 2 ** this.attempt++, 5_000);
    this.reconnectTimer = setTimeout(() => this.connect(), delay);
  }
}
