import { Page, request, APIRequestContext } from "@playwright/test";

const BACKEND = "http://127.0.0.1:3100";

export type Authenticated = { hostId: number; token: string; email: string };

// Phase 5-3: backend を直叩きで signup → JWT を localStorage に書く (zoom helpers.ts と同形)。
// 連続テスト間で email が衝突しないように uniqueEmail() を使う。
export function uniqueEmail(prefix = "test"): string {
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}@example.com`;
}

export async function authenticateViaApi(
  page: Page,
  opts: { email?: string; password?: string; name?: string; tz?: string } = {}
): Promise<Authenticated> {
  const email = opts.email ?? uniqueEmail("host");
  const password = opts.password ?? "supersecret123";
  const name = opts.name ?? "E2E Host";
  const tz = opts.tz ?? "Asia/Tokyo";

  const ctx = await request.newContext();
  const res = await ctx.post(`${BACKEND}/create-account`, {
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    data: { email, password, name, default_tz_id: tz },
  });
  if (!res.ok()) throw new Error(`signup failed: ${res.status()} ${await res.text()}`);

  const token = res.headers()["authorization"];
  if (!token) throw new Error("no Authorization header");

  // Host の id を /event_types index で確認 (空配列が返る前提、id は別経路で取得)
  // ここではメモから一旦欠落を許容し、後段の API で host_id を確認する。
  // 直接 host_id を取り出す代わりに、token を localStorage に入れて UI を起動する。
  await page.goto("http://127.0.0.1:3105/");
  await page.evaluate((t) => localStorage.setItem("calendly-jwt", t), token);

  return { hostId: -1, token, email };
}

export async function apiCreateEventType(
  ctx: APIRequestContext,
  token: string,
  payload: { slug: string; title: string; duration_minutes: number; max_advance_days?: number; min_notice_minutes?: number }
): Promise<number> {
  const res = await ctx.post(`${BACKEND}/event_types`, {
    headers: { "Content-Type": "application/json", Accept: "application/json", Authorization: token },
    data: { active: true, max_advance_days: 365, min_notice_minutes: 0, ...payload },
  });
  if (!res.ok()) throw new Error(`create event_type failed: ${res.status()} ${await res.text()}`);
  return (await res.json()).id;
}

export async function apiCreateAvailabilityRule(
  ctx: APIRequestContext,
  token: string,
  payload: { rrule?: string; start_time_of_day?: string; end_time_of_day?: string; tz_id?: string } = {}
): Promise<number> {
  const res = await ctx.post(`${BACKEND}/availability_rules`, {
    headers: { "Content-Type": "application/json", Accept: "application/json", Authorization: token },
    data: {
      rrule: payload.rrule ?? "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR",
      start_time_of_day: payload.start_time_of_day ?? "09:00:00",
      end_time_of_day: payload.end_time_of_day ?? "17:00:00",
      tz_id: payload.tz_id ?? "Asia/Tokyo",
    },
  });
  if (!res.ok()) throw new Error(`create rule failed: ${res.status()} ${await res.text()}`);
  return (await res.json()).id;
}

export async function apiCreateBooking(
  ctx: APIRequestContext,
  payload: { event_type_id: number; start_at: string; invitee_email: string; invitee_tz_id?: string }
) {
  const res = await ctx.post(`${BACKEND}/bookings`, {
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    data: { invitee_tz_id: "Asia/Tokyo", ...payload },
  });
  return res;
}

// Host id を取得するヘルパ — index API は host_id を含む event_type を返す。
export async function getHostIdFromEventType(ctx: APIRequestContext, token: string, eventTypeId: number): Promise<number> {
  const res = await ctx.get(`${BACKEND}/event_types`, {
    headers: { "Content-Type": "application/json", Authorization: token },
  });
  const list = await res.json();
  const found = list.find((et: { id: number; host_id: number }) => et.id === eventTypeId);
  if (!found) throw new Error("event_type not found in index");
  return found.host_id;
}
