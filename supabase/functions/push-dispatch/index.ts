// RCNO-37 プッシュ通知を APNs へ送る。
// Cron（private.ruuuto_request_push_dispatch）から1分ごとに呼ばれる。
// 呼び出しには合言葉ヘッダー x-ruuuto-push-secret が必要（環境変数 PUSH_DISPATCH_SECRET と一致すること）。
//
// 環境変数
//   PUSH_DISPATCH_SECRET  Cron と共有する合言葉（16文字以上）
//   APNS_KEY_P8           APNs の署名鍵（.p8 の中身。PEM。改行は \n でもよい）
//   APNS_KEY_ID           署名鍵の Key ID
//   APNS_TEAM_ID          Apple Developer の Team ID
//   APNS_BUNDLE_ID        アプリの Bundle ID（apns-topic）
//   APNS_BASE_URL         （任意・試験用）送り先を固定する。未設定なら端末の環境で
//                         api.push.apple.com / api.sandbox.push.apple.com を使い分ける
// APNS_* がそろっていなければ、配信行は pending のまま残し、apns_not_configured を返す。
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

const CLAIM_LIMIT = 100;
const MAX_BATCHES = 5;
const TIME_BUDGET_MS = 40_000;
const CONCURRENCY = 10;
const REQUEST_TIMEOUT_MS = 10_000;
const JWT_TTL_MS = 50 * 60 * 1000;
const INVALID_REASONS = new Set(["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"]);

type Delivery = {
  id: string;
  event_id: string;
  kind: string;
  group_id: string;
  board_id: string;
  title: string;
  body: string;
  apns_token: string;
  environment: "sandbox" | "production";
  attempts: number;
};

type Outcome = "sent" | "retry" | "invalid" | "failed";

type Result = {
  id: string;
  outcome: Outcome;
  status_code: number | null;
  reason: string | null;
  apns_id: string | null;
};

type ApnsConfig = {
  keyPem: string;
  keyId: string;
  teamId: string;
  bundleId: string;
  baseUrl: string | null;
};

function timingSafeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  if (ea.length !== eb.length) return false;
  let diff = 0;
  for (let i = 0; i < ea.length; i++) diff |= ea[i] ^ eb[i];
  return diff === 0;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function apnsConfig(): ApnsConfig | null {
  const keyPem = Deno.env.get("APNS_KEY_P8") ?? "";
  const keyId = Deno.env.get("APNS_KEY_ID") ?? "";
  const teamId = Deno.env.get("APNS_TEAM_ID") ?? "";
  const bundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "";
  if (!keyPem || !keyId || !teamId || !bundleId) return null;
  const baseUrl = Deno.env.get("APNS_BASE_URL")?.replace(/\/+$/, "") || null;
  return { keyPem: keyPem.replace(/\\n/g, "\n"), keyId, teamId, bundleId, baseUrl };
}

function base64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// ES256 の署名トークン。50分使い回す（APNs は20分〜60分ごとの更新を求め、作り直しすぎると
// TooManyProviderTokenUpdates になる）。同時に送る複数の要求で1つのトークンを共有する。
let cachedJwt: { token: Promise<string>; keyId: string; expiresAt: number } | null = null;

function providerToken(config: ApnsConfig): Promise<string> {
  const now = Date.now();
  if (cachedJwt && cachedJwt.keyId === config.keyId && cachedJwt.expiresAt > now) return cachedJwt.token;
  const token = signProviderToken(config, now);
  cachedJwt = { token, keyId: config.keyId, expiresAt: now + JWT_TTL_MS };
  token.catch(() => (cachedJwt = null));
  return token;
}

async function signProviderToken(config: ApnsConfig, now: number): Promise<string> {
  const der = Uint8Array.from(
    atob(config.keyPem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "")),
    (c) => c.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = base64url(JSON.stringify({ alg: "ES256", kid: config.keyId }));
  const claims = base64url(JSON.stringify({ iss: config.teamId, iat: Math.floor(now / 1000) }));
  const input = `${header}.${claims}`;
  // WebCrypto の ECDSA 署名は r||s（64バイト）で、JWT の ES256 の形そのまま
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(input)),
  );
  return `${input}.${base64url(signature)}`;
}

// APNs は HTTP/2 だけを受け付ける。使えるなら HTTP/2 に固定したクライアントを使う
// （試験用の平文 http の送り先でも HTTP/2 で話す）。
let http2Client: unknown = null;
function httpClient(): unknown {
  if (http2Client) return http2Client;
  // deno-lint-ignore no-explicit-any
  const create = (Deno as any).createHttpClient;
  if (typeof create === "function") {
    try {
      http2Client = create({ http1: false, http2: true });
    } catch (error) {
      console.warn("createHttpClient unavailable", String(error));
    }
  }
  return http2Client;
}

function classify(status: number, reason: string | null): Outcome {
  if (status === 200) return "sent";
  if (status === 410) return "invalid";
  if (status === 400 && reason && INVALID_REASONS.has(reason)) return "invalid";
  // 403: 署名トークンの期限切れ・不正。設定の問題なので、トークンを作り直して後で送り直す
  if (status === 403 || status === 429 || status >= 500) return "retry";
  return "failed";
}

async function send(config: ApnsConfig, d: Delivery): Promise<Result> {
  const host = config.baseUrl ??
    (d.environment === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com");
  const payload = {
    aps: { alert: { title: d.title, body: d.body }, sound: "default" },
    event_id: d.event_id,
    kind: d.kind,
    group_id: d.group_id,
    board_id: d.board_id,
  };
  try {
    const jwt = await providerToken(config);
    const client = httpClient();
    const init: RequestInit & { client?: unknown } = {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": config.bundleId,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-collapse-id": d.event_id,
        "apns-expiration": String(Math.floor(Date.now() / 1000) + 6 * 60 * 60),
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    };
    if (client) init.client = client;
    const res = await fetch(`${host}/3/device/${d.apns_token}`, init);
    const text = await res.text();
    let reason: string | null = null;
    if (text) {
      try {
        reason = JSON.parse(text).reason ?? null;
      } catch {
        reason = null;
      }
    }
    const outcome = classify(res.status, reason);
    if (res.status === 403) cachedJwt = null;
    return { id: d.id, outcome, status_code: res.status, reason, apns_id: res.headers.get("apns-id") };
  } catch (error) {
    const name = error instanceof Error ? error.name : "Error";
    return { id: d.id, outcome: "retry", status_code: null, reason: `NetworkError:${name}`, apns_id: null };
  }
}

async function sendAll(config: ApnsConfig, deliveries: Delivery[]): Promise<Result[]> {
  const results: Result[] = new Array(deliveries.length);
  let next = 0;
  const workers = Array.from({ length: Math.min(CONCURRENCY, deliveries.length) }, async () => {
    while (next < deliveries.length) {
      const i = next++;
      results[i] = await send(config, deliveries[i]);
    }
  });
  await Promise.all(workers);
  return results;
}

Deno.serve(async (req) => {
  const expected = Deno.env.get("PUSH_DISPATCH_SECRET") ?? "";
  const given = req.headers.get("x-ruuuto-push-secret") ?? "";
  if (req.method !== "POST" || expected.length < 16 || !timingSafeEqual(given, expected)) {
    return json({ error: "forbidden" }, 403);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const { data: fanout, error: fanoutError } = await supabase.rpc("ruuuto_admin_push_fanout");
  if (fanoutError) {
    console.error("push fanout failed", fanoutError.code, fanoutError.message);
    return json({ error: "fanout_failed" }, 500);
  }

  const config = apnsConfig();
  if (!config) {
    const result = { status: "apns_not_configured", fanout };
    console.log("push-dispatch", JSON.stringify(result));
    return json(result);
  }

  const started = Date.now();
  const totals = { claimed: 0, sent: 0, retry: 0, invalid: 0, failed: 0 };
  for (let batch = 0; batch < MAX_BATCHES && Date.now() - started < TIME_BUDGET_MS; batch++) {
    const { data: claimed, error: claimError } = await supabase.rpc("ruuuto_admin_push_claim", {
      p_limit: CLAIM_LIMIT,
    });
    if (claimError) {
      console.error("push claim failed", claimError.code, claimError.message);
      return json({ error: "claim_failed", fanout, ...totals }, 500);
    }
    const deliveries = (claimed ?? []) as Delivery[];
    if (deliveries.length === 0) break;
    totals.claimed += deliveries.length;

    const results = await sendAll(config, deliveries);
    const { data: recorded, error: recordError } = await supabase.rpc("ruuuto_admin_push_record", {
      p_results: results,
    });
    if (recordError) {
      // 記録できなかった行は送信中のまま残り、10分後に受け取り直される
      console.error("push record failed", recordError.code, recordError.message);
      return json({ error: "record_failed", fanout, ...totals }, 500);
    }
    for (const k of ["sent", "retry", "invalid", "failed"] as const) totals[k] += recorded?.[k] ?? 0;
    if (deliveries.length < CLAIM_LIMIT) break;
  }

  const result = { status: "ok", fanout, ...totals };
  console.log("push-dispatch", JSON.stringify(result));
  return json(result);
});
