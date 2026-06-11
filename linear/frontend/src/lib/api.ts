import type {
  BootstrapResponse,
  DeltaResponse,
  MutationRequest,
  MutationResponse,
  SyncOp,
  TriageResponse,
} from '@linear/shared';
import { TransportHttpError, type Transport } from '@linear/client-sync';
import { API_URL } from './config';
import { getSession, setSession } from './session';

/**
 * fetch wrapper。401 は session を破棄して /login へ (frontend coding rules)。
 * 4xx は TransportHttpError → SyncEngine が rollback と解釈する (ADR 0003)。
 */
async function api<T>(
  path: string,
  init: RequestInit = {},
  token?: string,
): Promise<T> {
  const auth = token ?? getSession()?.token;
  const res = await fetch(`${API_URL}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(auth ? { Authorization: `Bearer ${auth}` } : {}),
      ...init.headers,
    },
  });
  if (res.status === 401 && typeof window !== 'undefined' && auth) {
    setSession(null);
    window.location.href = '/login';
  }
  if (!res.ok) throw new TransportHttpError(res.status);
  return (await res.json()) as T;
}

/** SyncEngine へ注入する HTTP transport */
export class HttpTransport implements Transport {
  constructor(private readonly token: string) {}

  bootstrap(workspaceId: number): Promise<BootstrapResponse> {
    return api(`/sync/bootstrap?workspaceId=${workspaceId}`, {}, this.token);
  }

  delta(workspaceId: number, since: number): Promise<DeltaResponse> {
    return api(
      `/sync/delta?workspaceId=${workspaceId}&since=${since}`,
      {},
      this.token,
    );
  }

  mutate(req: MutationRequest): Promise<MutationResponse> {
    return api(
      '/mutations',
      { method: 'POST', body: JSON.stringify(req) },
      this.token,
    );
  }
}

interface AuthResult {
  token: string;
  user: { id: number; email: string; name: string };
  workspace: { id: number; name: string; urlKey: string };
}

export function signup(
  email: string,
  password: string,
  name: string,
): Promise<AuthResult> {
  return api('/auth/signup', {
    method: 'POST',
    body: JSON.stringify({ email, password, name }),
  });
}

export async function login(email: string, password: string) {
  const res = await api<Omit<AuthResult, 'workspace'>>('/auth/login', {
    method: 'POST',
    body: JSON.stringify({ email, password }),
  });
  const me = await api<{
    workspaces: Array<{ id: number; name: string; urlKey: string }>;
  }>('/auth/me', {}, res.token);
  const workspace = me.workspaces[0];
  if (!workspace) throw new Error('no workspace');
  return { ...res, workspace };
}

export function triageIssue(
  workspaceId: number,
  issueId: number,
): Promise<TriageResponse> {
  return api('/ai/triage', {
    method: 'POST',
    body: JSON.stringify({ workspaceId, issueId }),
  });
}

export interface WorkspaceListItem {
  id: number;
  name: string;
  urlKey: string;
  role: 'admin' | 'member';
}

/** workspace switcher 用 (招待された workspace は /auth/me で発見する) */
export async function fetchWorkspaces(): Promise<WorkspaceListItem[]> {
  const me = await api<{ workspaces: WorkspaceListItem[] }>('/auth/me');
  return me.workspaces;
}

export function issueActivity(
  workspaceId: number,
  issueId: number,
): Promise<{ ops: SyncOp[] }> {
  return api(`/sync/activity?workspaceId=${workspaceId}&issueId=${issueId}`);
}
