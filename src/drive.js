/* تفويض Google Drive من الخادم: موافقة واحدة من صاحب الحساب، ثم رمز
   تحديث دائم يخزن في القاعدة، والوركر وحده يستبدله برمز وصول قصير كلما
   احتاجه المتصفح. لا نافذة اذن بعد المرة الاولى مهما اعاد تحميل الصفحة.
   يحتاج GOOGLE_CLIENT_ID (متغير عام) وGOOGLE_CLIENT_SECRET (سر). */
import { rpc } from "./notify.js";
import { hmacHex } from "./telegram-documents.js";

const GOOGLE_AUTH = "https://accounts.google.com/o/oauth2/v2/auth";
const GOOGLE_TOKEN = "https://oauth2.googleapis.com/token";
/* نفس نطاق درايف المستعمل في المتصفح: ملفات التطبيق وحدها لا كل الدرايف */
const DRIVE_SCOPE = "https://www.googleapis.com/auth/drive.file";
const STATE_MAX_AGE = 10 * 60 * 1000;

export function driveServerConfigured(env) {
  return !!(env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET);
}

function redirectUri(origin) {
  return `${origin}/api/drive/oauth/callback`;
}

/* الحالة موقعة: تحمل الشركة وصاحب الطلب ووقته، فلا يزورها احد ولا تعاد */
async function signState(env, payload) {
  const raw = JSON.stringify(payload);
  const body = btoa(unescape(encodeURIComponent(raw))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const sig = (await hmacHex(env.WORKER_SECRET, body)).slice(0, 32);
  return `${body}.${sig}`;
}

async function readState(env, state) {
  const parts = String(state || "").split(".");
  if (parts.length !== 2) return null;
  const expected = (await hmacHex(env.WORKER_SECRET, parts[0])).slice(0, 32);
  if (expected !== parts[1]) return null;
  let payload;
  try {
    const b64 = parts[0].replace(/-/g, "+").replace(/_/g, "/");
    payload = JSON.parse(decodeURIComponent(escape(atob(b64))));
  } catch { return null; }
  if (!payload || !payload.org || !payload.user || !payload.at) return null;
  if (Date.now() - Number(payload.at) > STATE_MAX_AGE) return null;
  return payload;
}

/* بداية الربط: يعيد عنوان شاشة موافقة جوجل ليحول المتصفح نفسه اليه.
   لا نرد بتحويل مباشر لان تصفح المستخدم لا يحمل ترويسة الجلسة، فالتحقق
   يبقى في هذا النداء المصدق ثم ينتقل المتصفح بنفسه. */
export async function driveOAuthStart(env, user, body, origin) {
  const org = String((body && body.org) || "").trim();
  if (!org) return { error: "org required", status: 400 };
  const state = await signState(env, { org, user: user.id, at: Date.now() });
  const q = new URLSearchParams({
    client_id: env.GOOGLE_CLIENT_ID,
    redirect_uri: redirectUri(origin),
    response_type: "code",
    scope: DRIVE_SCOPE,
    access_type: "offline",
    include_granted_scopes: "true",
    /* consent مرة واحدة: بدونها لا ترسل جوجل رمز تحديث في المرات التالية */
    prompt: "consent",
    state,
  });
  return { url: `${GOOGLE_AUTH}?${q}` };
}

/* عودة جوجل: نبدل الرمز المؤقت برمز تحديث دائم ونخزنه، ثم نرجعه للاعدادات */
export async function driveOAuthCallback(env, url) {
  const back = (q) => Response.redirect(`${url.origin}/app/settings.html?drive=${q}#storageCard`, 302);
  if (url.searchParams.get("error")) return back("denied");
  const code = url.searchParams.get("code");
  const st = await readState(env, url.searchParams.get("state"));
  if (!code || !st) return back("failed");

  try {
    const res = await fetch(GOOGLE_TOKEN, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        code,
        client_id: env.GOOGLE_CLIENT_ID,
        client_secret: env.GOOGLE_CLIENT_SECRET,
        redirect_uri: redirectUri(url.origin),
        grant_type: "authorization_code",
      }),
    });
    const data = await res.json().catch(() => null);
    if (!res.ok || !data || !data.refresh_token) return back("failed");

    const saved = await rpc(env, "drive_conn_save", {
      p_secret: env.WORKER_SECRET, p_org: st.org, p_user: st.user, p_refresh: data.refresh_token,
    });
    if (!saved || saved.status !== "saved") return back("failed");
    return back("done");
  } catch {
    return back("failed");
  }
}

/* رمز وصول قصير للمتصفح: يولد من رمز التحديث المخزن بلا اي تدخل من العميل */
export async function driveAccessTokenFor(env, user, body) {
  const org = String((body && body.org) || "").trim();
  if (!org) return { error: "org required", status: 400 };

  const row = await rpc(env, "drive_conn_token", { p_secret: env.WORKER_SECRET, p_org: org, p_user: user.id });
  if (!row || row.status === "not_member") return { error: "not_member", status: 403 };
  if (row.status === "not_connected") return { error: "not_connected", status: 409 };

  const res = await fetch(GOOGLE_TOKEN, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: env.GOOGLE_CLIENT_ID,
      client_secret: env.GOOGLE_CLIENT_SECRET,
      refresh_token: row.refresh_token,
      grant_type: "refresh_token",
    }),
  });
  const data = await res.json().catch(() => null);
  /* سحب المستخدم الاذن من حسابه في جوجل: ننسى الرمز الميت ليعيد الربط مرة */
  if (!res.ok || !data || !data.access_token) {
    if (res.status === 400 || res.status === 401) {
      try { await rpc(env, "drive_conn_forget", { p_secret: env.WORKER_SECRET, p_org: org, p_user: user.id }); } catch { /* تجاهل */ }
      return { error: "reconnect_required", status: 409 };
    }
    return { error: "token_failed", status: 502 };
  }
  return { access_token: data.access_token, expires_in: Number(data.expires_in) || 3600 };
}

/* كل مسارات /api/drive في مكان واحد، فلا يتضخم الوركر: يستقبل authedUser
   منه لان التحقق من جلسة سوبابيس يعيش هناك. */
export async function handleDrive(request, env, url, authedUser, json) {
  const path = url.pathname;
  if (!driveServerConfigured(env)) return json({ error: "drive not configured" }, 503);
  if (path === "/api/drive/oauth/callback" && request.method === "GET") return await driveOAuthCallback(env, url);

  const routes = {
    "/api/drive/oauth/start": driveOAuthStartRoute,
    "/api/drive/token": driveTokenRoute,
    "/api/drive/forget": driveForgetRoute,
  };
  const fn = routes[path];
  if (!fn || request.method !== "POST") return null;

  const user = await authedUser(request, env);
  if (!user) return json({ error: "unauthorized" }, 401);
  let body = {};
  try { body = await request.json(); } catch { body = {}; }
  const out = await fn(env, user, body, url.origin);
  if (out && out.error) return json({ error: out.error }, out.status || 400);
  return json(out);
}

function driveOAuthStartRoute(env, user, body, origin) { return driveOAuthStart(env, user, body, origin); }
function driveTokenRoute(env, user, body) { return driveAccessTokenFor(env, user, body); }
function driveForgetRoute(env, user, body) { return driveForget(env, user, body); }

export async function driveForget(env, user, body) {
  const org = String((body && body.org) || "").trim();
  if (!org) return { error: "org required", status: 400 };
  const out = await rpc(env, "drive_conn_forget", { p_secret: env.WORKER_SECRET, p_org: org, p_user: user.id });
  if (!out || out.status === "not_member") return { error: "not_member", status: 403 };
  return { ok: true };
}
