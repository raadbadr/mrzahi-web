/* أجهزة البصمة: بروتوكول ZKTeco ADMS (PUSH) على mrzahi.com/iclock (ترحيل 0178).
   الجهاز يعرّف برقمه التسلسلي SN، ولا يقبل منه شيء قبل ان يسجله مالك الحساب او مشرفه من
   صفحة الحضور؛ والرقم غير المسجل يحفظ «اتصل» فقط ليرى صاحبه ان جهازه وصل.

   GET  /iclock/cdata?SN=…&options=all   مصافحة: اعدادات الارسال نصا
   POST /iclock/cdata?SN=…&table=ATTLOG  سطور البصمة: PIN\tYYYY-MM-DD HH:MM:SS\tStatus\tVerify\t…
   POST /iclock/cdata?table=OPERLOG|…    سجلات اخرى لا نحتاجها: «OK» كي لا يعيدها الجهاز
   GET  /iclock/getrequest?SN=…          نبض واستطلاع اوامر: «OK» بلا اوامر
   POST /iclock/devicecmd                ردود اوامر: «OK»

   الرد نص خام دائما؛ والجهاز يعيد ارسال ما لم يجب عليه بـ OK، والتكرار يمنعه فهرس فريد في القاعدة. */
import { rpc } from "./notify.js";

const MAX_BODY = 512 * 1024;
const hits = new Map();

function text(body, status = 200) {
  return new Response(body, { status, headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" } });
}

/* حد بسيط لكل رقم تسلسلي: الجهاز ينبض كل بضع ثوان، فما فوق 120 في الدقيقة عبث */
function limited(sn) {
  const now = Date.now();
  let b = hits.get(sn);
  if (!b || now - b.t >= 60_000) { b = { t: now, n: 0 }; hits.set(sn, b); }
  b.n += 1;
  if (hits.size > 5000) hits.clear();
  return b.n > 120;
}

export function parseAttlog(body) {
  const out = [];
  for (const raw of String(body || "").split(/\r?\n/)) {
    const line = raw.trim();
    if (!line) continue;
    const f = line.split("\t");
    const pin = String(f[0] || "").trim();
    const at = String(f[1] || "").trim();
    if (!pin || !/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}(:\d{2})?$/.test(at)) continue;
    out.push({ pin: pin.slice(0, 32), at: at.length === 16 ? at + ":00" : at, status: String(f[2] || "").trim().slice(0, 4) });
  }
  return out;
}

export async function handleIclock(request, env, url) {
  const path = url.pathname.replace(/\/+$/, "");
  const sn = String(url.searchParams.get("SN") || url.searchParams.get("sn") || "").trim().toUpperCase();
  const ip = request.headers.get("cf-connecting-ip") || "";
  if (!env.WORKER_SECRET) return text("ERROR", 503);
  if (!/^[A-Z0-9]{6,32}$/.test(sn)) return text("ERROR", 400);
  if (limited(sn)) return text("ERROR", 429);
  const secret = env.WORKER_SECRET;

  if (path === "/iclock/cdata" && request.method === "GET") {
    let st = "unknown";
    try { st = await rpc(env, "attendance_device_seen", { p_secret: secret, p_serial: sn, p_ip: ip }); } catch { st = "unknown"; }
    /* الجهاز غير المسجل يصافح ايضا فيظهر «اتصل»، لكن لا يطلب منه ارسال شيء حتى يسجل */
    const lines = [
      "GET OPTION FROM: " + sn,
      "ATTLOGStamp=None", "OPERLOGStamp=9999", "ATTPHOTOStamp=None",
      "ErrorDelay=30", "Delay=10", "TransTimes=00:00;14:05", "TransInterval=1",
      "TransFlag=" + (st === "active" ? "TransData AttLog" : ""),
      "TimeZone=3", "Realtime=1", "Encrypt=None",
    ];
    return text(lines.join("\n"));
  }

  if (path === "/iclock/cdata" && request.method === "POST") {
    const table = String(url.searchParams.get("table") || "").toUpperCase();
    const len = Number(request.headers.get("content-length") || 0);
    if (len > MAX_BODY) return text("ERROR", 413);
    const body = await request.text();
    if (body.length > MAX_BODY) return text("ERROR", 413);
    if (table !== "ATTLOG") return text("OK");
    const rows = parseAttlog(body);
    let res = null;
    try { res = await rpc(env, "attendance_device_ingest", { p_secret: secret, p_serial: sn, p_lines: rows, p_ip: ip }); }
    catch (e) { console.log("iclock ingest failed", sn, String((e && e.message) || e).slice(0, 200)); return text("ERROR", 500); }
    /* غير المسجل او الموقوف: OK كي لا يغرق الجهاز نفسه بالاعادة، ولا يحفظ منه شيء */
    if (!res || res.status !== "ok") return text("OK");
    return text("OK: " + rows.length);
  }

  if (path === "/iclock/getrequest") {
    try { await rpc(env, "attendance_device_seen", { p_secret: secret, p_serial: sn, p_ip: ip }); } catch { /* النبض لا يفشل الجهاز */ }
    return text("OK");
  }
  if (path === "/iclock/devicecmd") return text("OK");
  return text("OK");
}
