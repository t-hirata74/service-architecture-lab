'use client';

import {
  createContext,
  useContext,
  useEffect,
  useState,
  useSyncExternalStore,
  type ReactNode,
} from 'react';
import { SyncEngine, type EngineSnapshot } from '@linear/client-sync';
import type { MutationCommand } from '@linear/shared';
import { HttpTransport } from './api';
import { IdbSyncStorage } from './idb-storage';
import type { Session } from './session';
import { WsClient } from './ws-client';

interface SyncContextValue {
  engine: SyncEngine;
  session: Session;
  /** 直近の server 拒否 (rollback) 通知。UI は toast として出す */
  errors: string[];
}

const SyncContext = createContext<SyncContextValue | null>(null);

export function SyncProvider({
  session,
  children,
}: {
  session: Session;
  children: ReactNode;
}) {
  const [errors, setErrors] = useState<string[]>([]);
  // engine / ws は 1 度だけ生成する (frontend coding rules の urql Provider と同じ規律)
  const [ctx] = useState(() => {
    const engine = new SyncEngine({
      workspaceId: session.workspace.id,
      actorId: session.user.id,
      transport: new HttpTransport(session.token),
      storage: new IdbSyncStorage(),
      onMutationRejected: (entry) => {
        setErrors((prev) => [
          ...prev.slice(-4),
          `変更が拒否されました (${entry.command.type})`,
        ]);
      },
    });
    const ws = new WsClient(engine, session.workspace.id, session.token);
    return { engine, ws };
  });

  useEffect(() => {
    void ctx.engine.start();
    ctx.ws.start();
    return () => ctx.ws.stop();
  }, [ctx]);

  return (
    <SyncContext.Provider value={{ engine: ctx.engine, session, errors }}>
      {children}
    </SyncContext.Provider>
  );
}

function useSyncContext(): SyncContextValue {
  const ctx = useContext(SyncContext);
  if (!ctx) throw new Error('useSync must be used inside <SyncProvider>');
  return ctx;
}

/** engine の導出 state を React に接続する唯一の口 */
export function useSync(): EngineSnapshot & {
  mutate: (command: MutationCommand) => void;
  session: Session;
  errors: string[];
} {
  const { engine, session, errors } = useSyncContext();
  const snap = useSyncExternalStore(
    engine.subscribe,
    engine.getSnapshot,
    engine.getSnapshot,
  );
  return {
    ...snap,
    mutate: (command) => engine.mutate(command),
    session,
    errors,
  };
}
