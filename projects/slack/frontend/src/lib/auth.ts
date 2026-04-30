import { api, setToken, clearToken } from "./api";
import { disconnectCable } from "./cable";

export type Me = {
  id: number;
  display_name: string;
  email: string;
};

function extractToken(res: Response): string {
  const token = res.headers.get("Authorization");
  if (!token) throw new Error("認証トークンが返却されませんでした");
  return token;
}

async function readError(res: Response): Promise<string> {
  try {
    const body = await res.json();
    if (typeof body.error === "string") return body.error;
    if (Array.isArray(body.error)) return body.error.join(", ");
    if (body["field-error"]) return body["field-error"].join(": ");
    return JSON.stringify(body);
  } catch {
    return `${res.status} ${res.statusText}`;
  }
}

export async function signup(email: string, password: string, displayName: string): Promise<void> {
  const res = await api("/create-account", {
    method: "POST",
    body: JSON.stringify({ email, password, display_name: displayName }),
  });
  if (!res.ok) throw new Error(await readError(res));
  setToken(extractToken(res));
}

export async function login(email: string, password: string): Promise<void> {
  const res = await api("/login", {
    method: "POST",
    body: JSON.stringify({ email, password }),
  });
  if (!res.ok) throw new Error(await readError(res));
  setToken(extractToken(res));
}

export async function logout(): Promise<void> {
  try {
    await api("/logout", { method: "POST" });
  } finally {
    disconnectCable();
    clearToken();
  }
}

export async function fetchMe(): Promise<Me> {
  const res = await api("/me");
  if (!res.ok) throw new Error(await readError(res));
  return res.json();
}
