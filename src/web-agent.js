/* دردشة الاوامر داخل التطبيق: نفس وكيل البوت (telegram-agent) وادواته (mcp)، لكن بجلسة الموقع.
   امر المهندس رعد 2026-09-20: «نحتاج نضيف كمان دردشة بحيث اعطيه اوامر ويعدل بدلا من الوضع الحالي»،
   واختار: زر عائم في كل الشاشات، ولا كتابة الا بعرض ما سيحدث وانتظار «نفذ».

   POST /api/agent          { text, org_id?, lang? } → { text } او { pending, ask }
   POST /api/agent/confirm  { pending, org_id?, lang? } → { text, done }

   الكتابة تمر ببوابة writeGate في notify.js كما في تيليغرام: كل فعل (اضافة، انجاز، اسناد)
   يعود pending فيعرض على صاحبه، ولا ينفذ الا برسالة تاكيد ثانية. */

import { agentReply } from "./telegram-agent.js";
import { executeAction, describeAction } from "./telegram-actions.js";
import { rpc } from "./notify.js";

const LANGS = ["ar", "en", "fr", "ur"];
const ACTIONS = ["add", "done", "assign"];
/* حقول العنصر كما تقبلها telegram_add_item لا اكثر (نفس قائمة writeGate) */
const ITEM_KEYS = ["kind", "title", "client_name", "case_number", "violation_number", "amount", "due_at", "location", "notes", "category", "parent_id"];
const MAX_CHARS = 2000;
const RATE_MAX_PER_MIN = 12;
const buckets = new Map();

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });
}

function rateLimited(key) {
  const now = Date.now();
  let b = buckets.get(key);
  if (!b || now - b.start >= 60_000) { b = { start: now, count: 0 }; buckets.set(key, b); }
  b.count += 1;
  if (buckets.size > 5000) buckets.clear();
  return b.count > RATE_MAX_PER_MIN;
}

function langOf(body) {
  const l = String((body && body.lang) || "ar");
  return LANGS.indexOf(l) === -1 ? "ar" : l;
}

/* المنظمة من عضوية المستخدم في القاعدة لا من الطلب: الواجهة تقترح والقاعدة تقرر.
   وهي تعاد الى الواجهة كي يعرف صاحبها اين سيكتب قبل ان يؤكد. */
async function orgOf(env, userId, want) {
  let choices = [];
  try { choices = (await rpc(env, "telegram_org_choices", { p_secret: env.WORKER_SECRET, p_user_id: userId })) || []; } catch { choices = []; }
  if (!Array.isArray(choices) || !choices.length) return null;
  const pick = choices.filter((c) => c && String(c.id) === String(want || ""))[0];
  return pick || choices[0];
}

/* ما ترسله الواجهة بيان لا امر: الفعل المعلق يعاد بناؤه من حقول معروفة وحدها */
function cleanPending(p) {
  if (!p || typeof p !== "object") return null;
  const action = String(p.action || "");
  if (ACTIONS.indexOf(action) === -1) return null;
  const str = (v, n) => String(v == null ? "" : v).slice(0, n);
  if (action === "done") {
    const out = { action, query: str(p.query, 200), item_id: p.item_id ? str(p.item_id, 64) : null };
    return out.query || out.item_id ? out : null;
  }
  if (action === "assign") {
    const out = { action, query: str(p.query, 200), member: str(p.member, 120) };
    return out.query && out.member ? out : null;
  }
  const src = p.item && typeof p.item === "object" ? p.item : {};
  const item = {};
  for (const k of ITEM_KEYS) {
    const v = src[k];
    if (v == null || v === "") continue;
    item[k] = typeof v === "number" ? v : str(v, 500);
  }
  return item.title || item.kind ? { action, item } : null;
}

function ctxOf(user, org, lang, text, body) {
  const meta = (user && user.user_metadata) || {};
  return {
    text,
    lang,
    chatId: "web:" + user.id,          /* للحد من التكرار وحده؛ لا محادثة تيليغرام هنا */
    userId: user.id,
    name: meta.full_name || meta.name || user.email || "",
    orgId: org ? org.id : null,
    orgName: org ? org.name : "",
    userTimeZone: String((body && body.tz) || "Asia/Riyadh").slice(0, 64),
    userHour12: false,
  };
}

/** POST /api/agent — سؤال أو أمر؛ الجواب نص، والكتابة تعود pending للتأكيد */
export async function handleAgentChat(request, env, user) {
  if (!env.AI || !env.WORKER_SECRET) return json({ error: "unavailable" }, 503);
  let body;
  try { body = await request.json(); } catch { body = {}; }
  const text = String((body && body.text) || "").slice(0, MAX_CHARS).trim();
  if (!text) return json({ text: "" });
  if (rateLimited("agent:" + user.id)) return json({ error: "rate_limited" }, 429);
  const lang = langOf(body);
  const org = await orgOf(env, user.id, body && body.org_id);
  let out = null;
  try { out = await agentReply(env, ctxOf(user, org, lang, text, body)); } catch (e) { out = null; }
  if (!out) return json({ text: "", error: "no_answer" });
  if (out.pending) {
    const pending = cleanPending(out.pending);
    if (!pending) return json({ text: out.text || "" });
    return json({ pending, ask: describeAction(lang, pending, "Asia/Riyadh", false) });
  }
  return json({ text: String(out.text || "") });
}

/** POST /api/agent/confirm — ينفذ ما عرض قبل قليل، بعد ضغطة «نفذ» */
export async function handleAgentConfirm(request, env, user) {
  if (!env.WORKER_SECRET) return json({ error: "unavailable" }, 503);
  let body;
  try { body = await request.json(); } catch { body = {}; }
  const pending = cleanPending(body && body.pending);
  if (!pending) return json({ error: "bad_request" }, 400);
  if (rateLimited("agent:" + user.id)) return json({ error: "rate_limited" }, 429);
  const lang = langOf(body);
  let res;
  try { res = await executeAction(env, user.id, pending, lang); } catch (e) { return json({ error: "failed", detail: String((e && e.message) || e).slice(0, 200) }, 500); }
  /* ازرار تيليغرام (extra) لا شأن للويب بها: النص وحده يعرض، والواجهة تعيد رسم شاشتها */
  return json({ text: String((res && res.text) || ""), done: true, action: pending.action });
}
