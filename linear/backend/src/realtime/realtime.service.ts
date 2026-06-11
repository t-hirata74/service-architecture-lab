import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { WS_CLOSE_FORBIDDEN } from '@linear/shared';
import type { ServerWsMessage, SyncOp } from '@linear/shared';
import type { WebSocket } from 'ws';

const HEARTBEAT_INTERVAL_MS = 30_000;

interface TrackedSocket {
  workspaceId: number;
  userId: number;
  isAlive: boolean;
}

/**
 * workspace 単位の WS room 管理と op push (ADR 0005)。
 *
 * - push は at-most-once のヒント。配達保証は持たず、取りこぼしは client が
 *   seq 連続性で検出して delta で自己修復する (真実は sync log / ADR 0002)
 * - room は in-memory Map = backend 単一プロセス前提 (ローカル完結スコープ)。
 *   複数プロセス化には pub/sub 中継が必要 (Terraform 設計図で言及)
 * - heartbeat: 30s ごとに protocol ping。pong が返らない接続は terminate
 */
@Injectable()
export class RealtimeService implements OnModuleDestroy {
  private readonly logger = new Logger(RealtimeService.name);
  private readonly rooms = new Map<number, Set<WebSocket>>();
  private readonly sockets = new Map<WebSocket, TrackedSocket>();
  private readonly heartbeat: NodeJS.Timeout;

  constructor() {
    this.heartbeat = setInterval(() => this.pingAll(), HEARTBEAT_INTERVAL_MS);
    // テスト/CLI でプロセス終了を妨げない
    this.heartbeat.unref();
  }

  onModuleDestroy(): void {
    clearInterval(this.heartbeat);
    for (const socket of this.sockets.keys()) socket.terminate();
    this.rooms.clear();
    this.sockets.clear();
  }

  register(workspaceId: number, socket: WebSocket, userId: number): void {
    let room = this.rooms.get(workspaceId);
    if (!room) {
      room = new Set();
      this.rooms.set(workspaceId, room);
    }
    room.add(socket);
    this.sockets.set(socket, { workspaceId, userId, isAlive: true });
    socket.on('pong', () => {
      const tracked = this.sockets.get(socket);
      if (tracked) tracked.isAlive = true;
    });
  }

  unregister(socket: WebSocket): void {
    const tracked = this.sockets.get(socket);
    if (!tracked) return;
    this.sockets.delete(socket);
    const room = this.rooms.get(tracked.workspaceId);
    room?.delete(socket);
    if (room && room.size === 0) this.rooms.delete(tracked.workspaceId);
  }

  /** COMMIT 済み op を room へ push する (mutations.service から呼ばれる) */
  broadcastOps(workspaceId: number, ops: SyncOp[]): void {
    const room = this.rooms.get(workspaceId);
    if (!room || room.size === 0) return;
    for (const op of ops) {
      const message = JSON.stringify({
        type: 'op',
        op,
      } satisfies ServerWsMessage);
      for (const socket of room) {
        if (socket.readyState === socket.OPEN) socket.send(message);
      }
    }
  }

  send(socket: WebSocket, message: ServerWsMessage): void {
    if (socket.readyState === socket.OPEN) socket.send(JSON.stringify(message));
  }

  /** removeMember された本人の接続を明示的に切る (ADR 0006)。close → unregister の経路 */
  kick(workspaceId: number, userId: number): void {
    for (const [socket, tracked] of this.sockets) {
      if (tracked.workspaceId === workspaceId && tracked.userId === userId) {
        socket.close(WS_CLOSE_FORBIDDEN, 'removed from workspace');
      }
    }
  }

  roomSize(workspaceId: number): number {
    return this.rooms.get(workspaceId)?.size ?? 0;
  }

  private pingAll(): void {
    for (const [socket, tracked] of this.sockets) {
      if (!tracked.isAlive) {
        this.logger.warn(
          `terminating dead socket (workspace=${tracked.workspaceId})`,
        );
        socket.terminate(); // close イベント経由で unregister される
        continue;
      }
      tracked.isAlive = false;
      socket.ping();
    }
  }
}
