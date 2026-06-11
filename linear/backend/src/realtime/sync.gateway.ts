import { ForbiddenException, Logger } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import {
  OnGatewayConnection,
  OnGatewayDisconnect,
  WebSocketGateway,
} from '@nestjs/websockets';
import {
  WS_CLOSE_FORBIDDEN,
  WS_CLOSE_INVALID_PARAMS,
  WS_CLOSE_UNAUTHORIZED,
} from '@linear/shared';
import type { IncomingMessage } from 'node:http';
import type { WebSocket } from 'ws';
import { SyncService } from '../sync/sync.service';
import { WorkspacesService } from '../workspaces/workspaces.service';
import { RealtimeService } from './realtime.service';

interface JwtPayload {
  sub: number;
}

/**
 * 素の WebSocket gateway (ADR 0005)。
 * `ws://…/sync/ws?workspaceId=N&token=JWT` で接続する。
 * ブラウザの WebSocket API はヘッダを付けられないため token は query param で渡す
 * (ローカル完結スコープの割り切り。本番なら一時 ticket 化が定石)。
 *
 * 接続確立後すぐ hello (現在の lastSyncId) を送る。client はそこへ向けて
 * delta で catch-up してから op 適用を始める (ADR 0003)。
 */
@WebSocketGateway({ path: '/sync/ws' })
export class SyncGateway implements OnGatewayConnection, OnGatewayDisconnect {
  private readonly logger = new Logger(SyncGateway.name);

  constructor(
    private readonly jwt: JwtService,
    private readonly workspaces: WorkspacesService,
    private readonly sync: SyncService,
    private readonly realtime: RealtimeService,
  ) {}

  async handleConnection(
    client: WebSocket,
    request: IncomingMessage,
  ): Promise<void> {
    let workspaceId: number;
    let userId: number;
    try {
      const url = new URL(request.url ?? '/', 'http://localhost');
      workspaceId = Number(url.searchParams.get('workspaceId'));
      const token = url.searchParams.get('token') ?? '';
      if (!Number.isInteger(workspaceId) || workspaceId <= 0) {
        client.close(WS_CLOSE_INVALID_PARAMS, 'invalid workspaceId');
        return;
      }
      const payload = await this.jwt.verifyAsync<JwtPayload>(token);
      userId = payload.sub;
      await this.workspaces.assertMember(workspaceId, userId);
    } catch (e) {
      client.close(
        e instanceof ForbiddenException
          ? WS_CLOSE_FORBIDDEN
          : WS_CLOSE_UNAUTHORIZED,
        'connection rejected',
      );
      return;
    }

    this.realtime.register(workspaceId, client, userId);
    const lastSyncId = await this.sync.currentSyncId(workspaceId);
    this.realtime.send(client, { type: 'hello', workspaceId, lastSyncId });
    this.logger.log(
      `connected workspace=${workspaceId} (room=${this.realtime.roomSize(workspaceId)})`,
    );
  }

  handleDisconnect(client: WebSocket): void {
    this.realtime.unregister(client);
  }
}
