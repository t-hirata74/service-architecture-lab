'use client';

import { useEffect, useSyncExternalStore } from 'react';
import { useRouter } from 'next/navigation';
import { SyncProvider } from '@/lib/sync-provider';
import { getSession, subscribeSession } from '@/lib/session';
import { Workspace } from '@/components/Workspace';

export default function BoardPage() {
  const router = useRouter();
  // session は localStorage 由来の external store (SSR では null)
  const session = useSyncExternalStore(subscribeSession, getSession, () => null);

  useEffect(() => {
    if (!getSession()) router.replace('/login');
  }, [router]);

  if (!session) return null;
  return (
    <SyncProvider session={session}>
      <Workspace />
    </SyncProvider>
  );
}
