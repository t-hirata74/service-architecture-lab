import { api, setToken, clearToken } from "./api";

export type Me = { id: number; email: string };

async function authToken(path: string, email: string, password: string): Promise<void> {
  const res = await api(path, { method: "POST", body: JSON.stringify({ email, password }) });
  if (!res.ok) {
    let msg = `${res.status}`;
    try {
      msg = (await res.text()) || msg;
    } catch {
      /* noop */
    }
    throw new Error(msg.trim());
  }
  const body = await res.json(); // backend は {token, user_id} を返す
  if (!body.token) throw new Error("トークンが返却されませんでした");
  setToken(body.token);
}

export const register = (email: string, password: string) => authToken("/auth/register", email, password);
export const login = (email: string, password: string) => authToken("/auth/login", email, password);

export function logout(): void {
  clearToken();
}

export async function fetchMe(): Promise<Me> {
  const res = await api("/me");
  if (!res.ok) throw new Error("未認証");
  return res.json();
}
