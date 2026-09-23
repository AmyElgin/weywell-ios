// Database webhook target: call only when safety_notices is approved.
// Deploy with JWT verification disabled, then protect it with the separate
// WEYWELL_WEBHOOK_SECRET header. Never expose service-role/APNs/RC secrets
// to the iOS app or commit them to source control.

type Notice = {
  id: string; status: string; category: string; title: string;
  location_text: string; latitude: number; longitude: number; expires_at: string;
};
type Watch = {
  id: string; user_id: string; kind: "area" | "route"; radius_km: number;
  latitude: number | null; longitude: number | null;
  route_points: { latitude: number; longitude: number }[] | null;
};
type Device = { user_id: string; token: string; environment: "sandbox" | "production"; revenue_cat_user_id: string };

const projectURL = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const webhookSecret = Deno.env.get("WEYWELL_WEBHOOK_SECRET");
const rcSecret = Deno.env.get("REVENUECAT_SECRET_KEY");
const apnsKey = Deno.env.get("APNS_PRIVATE_KEY");
const apnsKeyID = Deno.env.get("APNS_KEY_ID");
const appleTeamID = Deno.env.get("APPLE_TEAM_ID");
const bundleID = Deno.env.get("APPLE_BUNDLE_ID") ?? "com.weywell.app";

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
}

async function database<T>(path: string, init: RequestInit = {}): Promise<T> {
  const response = await fetch(`${projectURL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: serviceKey, Authorization: `Bearer ${serviceKey}`,
      "content-type": "application/json", ...init.headers,
    },
  });
  if (!response.ok) throw new Error(`Database request failed: ${response.status}`);
  const text = await response.text();
  return text ? JSON.parse(text) as T : [] as T;
}

function metres(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const earth = 6371000;
  const x = (lon2 - lon1) * Math.PI / 180 * Math.cos((lat1 + lat2) * Math.PI / 360);
  const y = (lat2 - lat1) * Math.PI / 180;
  return earth * Math.hypot(x, y);
}

function matches(notice: Notice, watch: Watch): boolean {
  const maxDistance = watch.radius_km * 1000;
  if (watch.kind === "area") {
    return watch.latitude !== null && watch.longitude !== null &&
      metres(notice.latitude, notice.longitude, watch.latitude, watch.longitude) <= maxDistance;
  }
  const points = watch.route_points;
  if (!Array.isArray(points) || points.length < 2) return false;
  // Local tangent-plane segment distance, accurate enough for a 1 km road corridor.
  const scale = Math.cos(notice.latitude * Math.PI / 180);
  const x = (lon: number) => (lon - notice.longitude) * scale * 111195;
  const y = (lat: number) => (lat - notice.latitude) * 111195;
  for (let i = 1; i < points.length; i++) {
    const ax = x(points[i - 1].longitude), ay = y(points[i - 1].latitude);
    const bx = x(points[i].longitude), by = y(points[i].latitude);
    const length2 = (bx - ax) ** 2 + (by - ay) ** 2;
    const t = length2 ? Math.max(0, Math.min(1, -(ax * (bx - ax) + ay * (by - ay)) / length2)) : 0;
    if (Math.hypot(ax + t * (bx - ax), ay + t * (by - ay)) <= maxDistance) return true;
  }
  return false;
}

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function apnsBearer(): Promise<string> {
  if (!apnsKey || !apnsKeyID || !appleTeamID) throw new Error("APNs secrets not configured");
  const der = Uint8Array.from(atob(apnsKey.replace(/-----[^-]+-----/g, "").replace(/\s/g, "")), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const encoder = new TextEncoder();
  const head = base64url(encoder.encode(JSON.stringify({ alg: "ES256", kid: apnsKeyID })));
  const body = base64url(encoder.encode(JSON.stringify({ iss: appleTeamID, iat: Math.floor(Date.now() / 1000) })));
  const message = `${head}.${body}`;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(message));
  return `${message}.${base64url(new Uint8Array(signature))}`;
}

async function hasPlus(appUserID: string): Promise<boolean> {
  if (!rcSecret) throw new Error("RevenueCat secret not configured");
  const response = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserID)}`, {
    headers: { Authorization: `Bearer ${rcSecret}` },
  });
  if (!response.ok) throw new Error(`RevenueCat verification failed: ${response.status}`);
  const data = await response.json();
  const entitlement = data.subscriber?.entitlements?.weywell_plus;
  if (!entitlement) return false;
  return entitlement.expires_date == null || Date.parse(entitlement.expires_date) > Date.now();
}

async function sendToAPNs(notice: Notice, device: Device, bearer: string): Promise<boolean> {
  const host = device.environment === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  const label: Record<string, string> = {
    route_disruption: "Route disruption", unsafe_behaviour: "Unsafe behaviour",
    crime_reported: "Crime reported", neighbourhood: "Neighbourhood report",
  };
  const response = await fetch(`${host}/3/device/${device.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${bearer}`, "apns-topic": bundleID,
      "apns-push-type": "alert", "apns-priority": "10",
      "apns-expiration": `${Math.floor(Date.parse(notice.expires_at) / 1000)}`,
    },
    body: JSON.stringify({
      aps: { alert: { title: "Weywell alert nearby", body: `${label[notice.category] ?? "Safety notice"} near ${notice.location_text}. Open Weywell for details.` }, sound: "default" },
      notice_id: notice.id,
    }),
  });
  if (response.ok) return true;
  const detail = await response.json().catch(() => ({}));
  if (response.status === 410 || ["BadDeviceToken", "Unregistered"].includes(detail.reason)) {
    await database(`push_devices?user_id=eq.${device.user_id}&token=eq.${device.token}`, { method: "DELETE" });
  }
  throw new Error(`APNs rejected delivery: ${response.status} ${detail.reason ?? "unknown"}`);
}

Deno.serve(async request => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!webhookSecret || request.headers.get("x-weywell-webhook-secret") !== webhookSecret) return json({ error: "Unauthorized" }, 401);
  if (!rcSecret || !apnsKey || !apnsKeyID || !appleTeamID) return json({ error: "Push secrets incomplete" }, 503);
  try {
    const event = await request.json();
    const id = event.record?.id;
    if (event.type !== "UPDATE" || typeof id !== "string" || !/^[0-9a-f-]{36}$/i.test(id)) return json({ ignored: true });
    const notices = await database<Notice[]>(`safety_notices?select=id,status,category,title,location_text,latitude,longitude,expires_at&id=eq.${id}`);
    const notice = notices[0];
    if (!notice || notice.status !== "approved" || Date.parse(notice.expires_at) <= Date.now()) return json({ ignored: true });

    const bearer = await apnsBearer();
    const paidCache = new Map<string, boolean>();
    let sent = 0, failed = 0;
    for (let offset = 0; ; offset += 500) {
      const watches = await database<Watch[]>(`push_watches?select=id,user_id,kind,radius_km,latitude,longitude,route_points&enabled=eq.true&order=id&limit=500&offset=${offset}`);
      for (const watch of watches) {
        if (!matches(notice, watch)) continue;
        const devices = await database<Device[]>(`push_devices?select=user_id,token,environment,revenue_cat_user_id&user_id=eq.${watch.user_id}`);
        for (const device of devices) {
          if (!paidCache.has(device.revenue_cat_user_id)) paidCache.set(device.revenue_cat_user_id, await hasPlus(device.revenue_cat_user_id));
          if (!paidCache.get(device.revenue_cat_user_id)) continue;
          const existing = await database<{ notice_id: string }[]>(`push_deliveries?select=notice_id&notice_id=eq.${notice.id}&token=eq.${device.token}`);
          if (existing.length) continue;
          try {
            await sendToAPNs(notice, device, bearer);
            await database("push_deliveries", { method: "POST", headers: { Prefer: "resolution=ignore-duplicates" }, body: JSON.stringify({ watch_id: watch.id, notice_id: notice.id, token: device.token }) });
            sent++;
          } catch (error) {
            failed++;
            console.error("Push delivery failed", { notice: notice.id, watch: watch.id, error: String(error) });
          }
        }
      }
      if (watches.length < 500) break;
    }
    return json({ sent, failed }, failed ? 502 : 200);
  } catch (error) {
    console.error("Push webhook failed", String(error));
    return json({ error: "Delivery failed" }, 500);
  }
});
