// --- تقويم ICS ---------------------------------------------------------------
// GET /api/calendar/:token.ics — يعيد عناصر الشركة المرتبطة بالرمز كتقويم
// يُشترَك فيه من آبل/جوجل/أوتلوك. الرمز خاص بكل مستخدم ولا يكشف بيانات غيره.
import { rpc } from "./notify.js";
import { fitDevice } from "./arabic-shape.js";

function icsEscape(s) {
  return String(s == null ? "" : s)
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\;")
    .replace(/,/g, "\\,")
    .replace(/\r?\n/g, "\\n");
}

function icsDate(d) {
  const dt = new Date(d);
  if (Number.isNaN(dt.getTime())) return null;
  return dt.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
}

// طي الأسطر الطويلة حسب RFC 5545 (75 بايت)
function foldLine(line) {
  const out = [];
  let s = line;
  while (s.length > 73) {
    out.push(s.slice(0, 73));
    s = " " + s.slice(73);
  }
  out.push(s);
  return out.join("\r\n");
}

export function buildIcs(items, calName) {
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//MrZahi//mrzahi.com//AR",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    `X-WR-CALNAME:${icsEscape(calName || "MrZahi")}`,
    "X-WR-TIMEZONE:Asia/Riyadh",
  ];
  const stamp = icsDate(new Date());
  for (const it of items) {
    const due = icsDate(it.due_at);
    if (!due) continue;
    lines.push("BEGIN:VEVENT");
    lines.push(`UID:${it.id}@mrzahi.com`);
    lines.push(`DTSTAMP:${stamp}`);
    lines.push(`DTSTART:${due}`);
    lines.push(`DTEND:${due}`);
    lines.push(foldLine(`SUMMARY:${icsEscape(it.title)}`));
    const descParts = [];
    if (it.tracker_name) descParts.push(it.tracker_name);
    if (it.category) descParts.push(it.category);
    if (it.status) descParts.push(it.status);
    if (descParts.length) lines.push(foldLine(`DESCRIPTION:${icsEscape(descParts.join(" · "))}`));
    lines.push(`URL:https://mrzahi.com/app/dashboard.html?item=${it.id}`);
    lines.push(`STATUS:${it.status === "cancelled" ? "CANCELLED" : "CONFIRMED"}`);
    lines.push("END:VEVENT");
  }
  lines.push("END:VCALENDAR");
  return lines.join("\r\n") + "\r\n";
}

/* --- قناة الجهاز (شاشة زاهي) -------------------------------------------------
   الجهاز خادم لا عميل: لا TLS ولا NTP عنده، فيقرأ منه جسر محلي هذا المسار ويدفعه إليه.
   الصيغة التي يفهمها حرفيا: epoch|عنوان;epoch|عنوان — بإبوك محلي جاهز، وعنوان مشكل بصريا. */
const DEVICE_MAX_ITEMS = 4;
const DEVICE_MAX_BYTES = 83;
const DEVICE_TZ = "Asia/Riyadh";
const DEVICE_GRACE_MS = 30 * 60 * 1000; /* الجهاز يسقط الموعد بعد نصف ساعة من مروره */

/* ساعة الجهاز محلية بلا منطقة زمنية: نعطيه لحظة الحائط كما لو كانت UTC */
export function localEpoch(iso, tz) {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone: tz || DEVICE_TZ, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false }).formatToParts(d);
  const g = {};
  parts.forEach((p) => { g[p.type] = p.value; });
  return Math.floor(Date.UTC(Number(g.year), Number(g.month) - 1, Number(g.day), Number(g.hour === "24" ? 0 : g.hour), Number(g.minute), Number(g.second)) / 1000);
}

export function buildDevicePayload(items, opts) {
  const o = opts || {};
  const now = o.now || Date.now();
  const max = Math.max(1, Math.min(8, Number(o.max) || DEVICE_MAX_ITEMS));
  const rows = (Array.isArray(items) ? items : [])
    .filter((it) => it && it.due_at && !Number.isNaN(new Date(it.due_at).getTime()))
    .filter((it) => new Date(it.due_at).getTime() >= now - DEVICE_GRACE_MS)
    .sort((a, b) => new Date(a.due_at) - new Date(b.due_at))
    .slice(0, max);
  return rows.map((it) => localEpoch(it.due_at, o.tz) + "|" + fitDevice(it.title, DEVICE_MAX_BYTES)).join(";");
}

export async function handleDevice(token, env, url) {
  const safe = String(token || "").replace(/[^a-f0-9]/gi, "");
  if (!safe || safe.length < 16) return new Response("not found", { status: 404 });
  let feed;
  try { feed = await rpc(env, "calendar_feed", { p_token: safe }); } catch { feed = null; }
  if (!feed || typeof feed !== "object") return new Response("not found", { status: 404 });
  const max = url && url.searchParams ? Number(url.searchParams.get("n")) : 0;
  const body = buildDevicePayload(Array.isArray(feed.items) ? feed.items : [], { max });
  return new Response(body, {
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

export async function handleCalendar(token, env) {
  const safe = String(token || "").replace(/[^a-f0-9]/gi, "");
  if (!safe || safe.length < 16) return new Response("not found", { status: 404 });
  let feed;
  try { feed = await rpc(env, "calendar_feed", { p_token: safe }); } catch { feed = null; }
  if (!feed || typeof feed !== "object") return new Response("not found", { status: 404 });
  const calName = feed.org_name ? `MrZahi — ${feed.org_name}` : "MrZahi";
  return new Response(buildIcs(Array.isArray(feed.items) ? feed.items : [], calName), {
    headers: {
      "Content-Type": "text/calendar; charset=utf-8",
      "Content-Disposition": 'inline; filename="tracker.ics"',
      "Cache-Control": "private, max-age=300",
    },
  });
}
