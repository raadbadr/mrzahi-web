/* ============================================================
 * الربط المحاسبي (امر المهندس رعد 2026-09-23): «طريقة ربط سهلة مع قيود، او مع اي
 * منصة محاسبية يفضلها العميل». والاتجاه باختياره: الارسال من مستر زاهي الى المحاسبة،
 * فما يدخل من مصاريف وفواتير ينشا في المنصة المحاسبية فلا يدخل مرتين.
 *
 * - النواة عامة: سجل منصات (PROVIDERS)، واول ما فيه قيود. كل منصة جديدة محول هنا
 *   وقيمة في قيد provider بالقاعدة، بلا جدول ولا صفحة جديدة.
 * - كل ما يرسل ينشا «مسودة» عند المنصة (Draft)، فلا يصير قيدا معتمدا ولا فاتورة
 *   ضريبية الا حين يعتمده محاسب المنشاة بنفسه.
 * - لا يرسل الا ما انشئ بعد الربط، ولا يرسل عنصر مرتين: يحجز قبل الارسال
 *   (acct_claim)، ويحمل مرجعا ثابتا مشتقا منه (MZ-…)، فان انقطع الرد بعد وصول الطلب
 *   وجد عند الاعادة بمرجعه ولم ينشا ثانية.
 * - مفتاح المنصة في supabase_vault، لا يصل المتصفح ابدا، والوركر يقراه بسره.
 * ============================================================ */
import { rpc } from "./notify.js";

const TIMEOUT_MS = 15000;

/* ---------- التصنيف: كلمات شاشة المصاريف نفسها ومنطق مطابقتها (dashboard.3/script.1.js) ---------- */
const EXPENSE_WORDS = ["مصروف", "مصاريف", "expense", "expenses", "dépense", "اخراجات"];
const LETTER = /[A-Za-z0-9؀-ۿ]/;
const AR_PREFIX = ["ال", "وال", "فال", "بال", "كال", "لل"];

function hasWord(text, word) {
  const hay = String(text || "").toLowerCase();
  const needle = String(word || "").toLowerCase();
  if (!hay || !needle) return false;
  let from = 0;
  for (;;) {
    const at = hay.indexOf(needle, from);
    if (at === -1) return false;
    const after = hay.charAt(at + needle.length);
    const okAfter = !after || !LETTER.test(after);
    let okBefore = at === 0 || !LETTER.test(hay.charAt(at - 1));
    if (!okBefore) {
      for (const pre of AR_PREFIX) {
        if (at >= pre.length && hay.slice(at - pre.length, at) === pre &&
            (at - pre.length === 0 || !LETTER.test(hay.charAt(at - pre.length - 1)))) { okBefore = true; break; }
      }
    }
    if (okBefore && okAfter) return true;
    from = at + 1;
  }
}

/* نوع العنصر عند المحاسبة: فاتورة بيع، او فاتورة مورد، او مصروف، او لا شيء */
export function itemKind(item) {
  const d = (item && item.data) || {};
  if (d.document_kind) return null;
  if (d.fin_dir === "in") return "sales_invoice";
  if (d.fin_dir === "out") return "purchase_bill";
  const cat = String((item && item.category) || "").trim();
  const text = cat || String((item && item.title) || "");
  return EXPENSE_WORDS.some((w) => hasWord(text, w)) ? "expense" : null;
}

/* تاريخ يوم بتوقيت الرياض (UTC+3 بلا توقيت صيفي) */
function riyadhDay(iso) {
  const t = Date.parse(iso || "");
  if (!Number.isFinite(t)) return "";
  return new Date(t + 3 * 3600 * 1000).toISOString().slice(0, 10);
}
function isDay(v) { return /^\d{4}-\d{2}-\d{2}$/.test(String(v || "")); }
function num(v) { const n = Number(v); return Number.isFinite(n) ? n : 0; }
function round2(n) { return Math.round(num(n) * 100) / 100; }
/* المرجع معرف العنصر كاملا (32 محرفا): لا يتصادم عنصران ابدا، فالعثور عليه عند
   الاعادة دليل على ان المستند له هو لا لغيره */
function refFor(item) { return "MZ-" + String(item.id || "").replace(/-/g, "").toUpperCase(); }
function posInt(v) { const n = Number(v); return Number.isInteger(n) && n > 0 ? n : null; }

/* ============================================================
 * قيود — https://apidoc.qoyod.com (مجموعة Postman الرسمية، الاصدار 2.0)
 * المصادقة: رأس API-KEY يولده العميل من الاعدادات العامة في حسابه على قيود.
 * ============================================================ */
const QOYOD_BASE = "https://api.qoyod.com/2.0";

async function qoyodCall(key, method, path, body) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const headers = { "API-KEY": key, Accept: "application/json" };
    if (body) headers["Content-Type"] = "application/json";
    const res = await fetch(QOYOD_BASE + path, { method, headers, body: body ? JSON.stringify(body) : undefined, signal: ctrl.signal });
    const text = await res.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch { data = null; }
    return { ok: res.ok, status: res.status, data, text: text.slice(0, 600) };
  } catch (e) {
    return { ok: false, status: 0, data: null, text: e && e.name === "AbortError" ? "timeout" : String((e && e.message) || e).slice(0, 200) };
  } finally {
    clearTimeout(timer);
  }
}

/* رسالة الخطا كما تعيدها قيود، مختصرة */
function qoyodError(r) {
  const d = r && r.data;
  let msg = "";
  if (d && typeof d === "object") {
    if (typeof d.message === "string") msg = d.message;
    else if (typeof d.error === "string") msg = d.error;
    else if (d.errors) msg = typeof d.errors === "string" ? d.errors : JSON.stringify(d.errors);
  }
  if (!msg) msg = (r && r.text) || "";
  return ("http " + ((r && r.status) || 0) + (msg ? ": " + msg : "")).slice(0, 400);
}

/* القوائم مقسمة صفحات (page و per_page)، و404 مع البحث تعني لا نتيجة */
async function qoyodList(key, resource, field, query, maxPages) {
  let out = [];
  for (let page = 1; page <= (maxPages || 5); page++) {
    const r = await qoyodCall(key, "GET", `/${resource}?page=${page}&per_page=100${query || ""}`);
    if (r.status === 404) break;
    if (!r.ok) return { error: r };
    const rows = (r.data && Array.isArray(r.data[field])) ? r.data[field] : [];
    out = out.concat(rows);
    if (rows.length < 100) break;
  }
  return { rows: out };
}

function authStop(r) { return r && (r.status === 401 || r.status === 403); }
function rateStop(r) { return r && r.status === 429; }

const qoyod = {
  key: "qoyod",
  names: { ar: "قيود", en: "Qoyod", fr: "Qoyod", ur: "قیود" },

  /* المفتاح صحيح ان اعادت قيود قائمة الفروع؛ 401 مفتاح مرفوض */
  async verify(key) {
    const r = await qoyodCall(key, "GET", "/inventories?page=1&per_page=100");
    if (authStop(r)) return { ok: false, error: "invalid_key" };
    if (!r.ok) return { ok: false, error: "provider_error", detail: qoyodError(r) };
    return { ok: true };
  },

  /* ما يختار منه صاحب الحساب: الفرع او المستودع، وحساب المصروفات، ومنتج فواتير البيع، والمورد الافتراضي */
  async lookups(key) {
    const [inv, acc, prod, ven] = await Promise.all([
      qoyodList(key, "inventories", "inventories", "", 3),
      qoyodList(key, "accounts", "accounts", "", 5),
      qoyodList(key, "products", "products", "", 5),
      qoyodList(key, "vendors", "vendors", "", 5),
    ]);
    const bad = [inv, acc, prod, ven].find((x) => x.error);
    if (bad) return { error: authStop(bad.error) ? "invalid_key" : "provider_error", detail: qoyodError(bad.error) };
    return {
      inventories: inv.rows.map((x) => ({ id: x.id, name: x.ar_name || x.name || String(x.id) })),
      expense_accounts: acc.rows
        .filter((a) => String(a.type || "") === "Expense" && String(a.status || "Active") !== "Inactive")
        .map((a) => ({ id: a.id, name: a.name_ar || a.name_en || String(a.id), code: a.code || "" })),
      products: prod.rows
        .filter((p) => p.is_sold !== false)
        .map((p) => ({ id: p.id, name: p.name_ar || p.name_en || String(p.id) })),
      vendors: ven.rows
        .filter((v) => String(v.status || "Active") !== "Inactive")
        .map((v) => ({ id: v.id, name: v.name || v.organization || String(v.id) })),
    };
  },

  /* جهة بالاسم نفسه حرفا، والا تنشا باسمها. collection: vendors او customers */
  async contactId(ctx, collection, name) {
    const clean = String(name || "").trim();
    if (!clean) return null;
    const cacheKey = collection + "\u0001" + clean;
    if (ctx.cache.has(cacheKey)) return ctx.cache.get(cacheKey);
    const found = await qoyodCall(ctx.key, "GET", `/${collection}?q[name_eq]=${encodeURIComponent(clean)}`);
    if (!found.ok && found.status !== 404) throw Object.assign(new Error(qoyodError(found)), { resp: found });
    const rows = (found.data && Array.isArray(found.data[collection])) ? found.data[collection] : [];
    const hit = rows.find((c) => String(c.name || "").trim() === clean);
    let id = hit ? hit.id : null;
    if (!id) {
      const made = await qoyodCall(ctx.key, "POST", `/${collection}`, { contact: { name: clean } });
      if (!made.ok) throw Object.assign(new Error(qoyodError(made)), { resp: made });
      id = made.data && made.data.contact && made.data.contact.id;
    }
    ctx.cache.set(cacheKey, id || null);
    return id || null;
  },

  /* حساب مصروفات باسم بند العنصر نفسه ان وجد، والا الافتراضي المختار */
  async expenseAccount(ctx, item) {
    const cat = String(item.category || "").trim().toLowerCase();
    if (cat && ctx.accounts === null) {
      const acc = await qoyodList(ctx.key, "accounts", "accounts", "", 5);
      ctx.accounts = acc.error ? [] : acc.rows.filter((a) => String(a.type || "") === "Expense");
    }
    if (cat && ctx.accounts) {
      const hit = ctx.accounts.find((a) => [a.name_ar, a.name_en].some((n) => String(n || "").trim().toLowerCase() === cat));
      if (hit) return hit.id;
    }
    return posInt(ctx.settings.expense_account_id);
  },

  /* مستند بمرجعه: لاعادة لم تعرف نتيجة سابقتها */
  async findByRef(ctx, resource, ref) {
    const r = await qoyodCall(ctx.key, "GET", `/${resource}?q[reference_eq]=${encodeURIComponent(ref)}`);
    const rows = (r.ok && r.data && Array.isArray(r.data[resource])) ? r.data[resource] : [];
    return rows.find((x) => String(x.reference || "") === ref) || null;
  },

  async push(ctx, item, kind) {
    const s = ctx.settings || {};
    const d = item.data || {};
    const ref = refFor(item);
    const title = String(item.title || "").trim() || ref;
    const issue = isDay(d.invoice_date) ? d.invoice_date : (riyadhDay(item.due_at) || riyadhDay(item.created_at));
    const due = riyadhDay(item.due_at) || issue;
    const inventory = posInt(s.inventory_id);
    if (!inventory) return { status: "waiting", error: "no_inventory" };
    const vat = String(d.vat_mode || "");

    if (kind === "sales_invoice") {
      const product = posInt(s.sales_product_id);
      if (!product) return { status: "waiting", error: "no_sales_product" };
      let unit, taxPercent, inclusive;
      if (vat === "exclusive") { unit = round2(d.base_sar); taxPercent = 15; inclusive = false; }
      else if (vat === "inclusive") { unit = round2(d.total_sar); taxPercent = 15; inclusive = true; }
      else { unit = round2(d.total_sar != null ? d.total_sar : item.amount); taxPercent = 0; inclusive = false; }
      if (!(unit > 0)) return { status: "waiting", error: "no_amount" };
      const customer = await this.contactId(ctx, "customers", item.client_name);
      if (!customer) return { status: "waiting", error: "no_customer" };
      const body = { invoice: {
        contact_id: customer, reference: ref, description: title, issue_date: issue, due_date: due,
        status: "Draft", inventory_id: inventory, draft_if_out_of_stock: true,
        line_items: [{ product_id: product, description: title, quantity: 1, unit_price: unit, tax_percent: taxPercent, is_inclusive: inclusive }],
      } };
      return await this.create(ctx, "invoices", "invoice", body, ref);
    }

    /* المصروف وفاتورة المورد: «فاتورة مبسطة» (simple_bill) بحساب مصروفات لا بمنتج */
    let total, taxId, inclusive;
    if (kind === "purchase_bill") {
      if (vat === "exclusive") { total = round2(d.base_sar); taxId = "1"; inclusive = false; }
      else if (vat === "inclusive") { total = round2(d.total_sar); taxId = "1"; inclusive = true; }
      else { total = round2(d.total_sar != null ? d.total_sar : item.amount); taxId = "3"; inclusive = false; }
    } else {
      total = round2(item.amount);
      if (s.expense_tax === "exempt") { taxId = "3"; inclusive = false; }
      else { taxId = "1"; inclusive = true; }   /* المبلغ المدخل هو المدفوع فعلا، شامل الضريبة */
    }
    if (!(total > 0)) return { status: "waiting", error: "no_amount" };
    const account = await this.expenseAccount(ctx, item);
    if (!account) return { status: "waiting", error: "no_expense_account" };
    let vendor = await this.contactId(ctx, "vendors", item.client_name);
    if (!vendor) vendor = posInt(s.default_vendor_id);
    if (!vendor) return { status: "waiting", error: "no_vendor" };
    const body = { simple_bill: {
      contact_id: vendor, status: "Draft", issue_date: issue, reference: ref, inventory_id: inventory,
      simple_bill_items_attributes: [{ expense_category_id: account, description: title, total_amount: total, tax_id: taxId, is_inclusive: inclusive }],
    } };
    return await this.create(ctx, "simple_bills", "simple_bill", body, ref);
  },

  async create(ctx, resource, field, body, ref) {
    const r = await qoyodCall(ctx.key, "POST", `/${resource}`, body);
    if (r.ok) {
      const doc = r.data && r.data[field];
      return { status: "sent", external_id: doc && doc.id != null ? String(doc.id) : null, ref: (doc && doc.reference) || ref };
    }
    if (authStop(r)) return { status: "failed", error: "invalid_key", stop: true };
    if (rateStop(r)) return { status: "failed", error: "rate_limited", stop: true };
    /* المرجع مستعمل: ارسال سابق وصل ولم يصل رده، فيؤخذ الموجود ولا ينشا ثان */
    if (r.status >= 400 && r.status < 500 && /reference/i.test(r.text || "")) {
      const existing = await this.findByRef(ctx, resource, ref);
      if (existing) return { status: "sent", external_id: String(existing.id), ref };
    }
    return { status: "failed", error: qoyodError(r) };
  },
};

const PROVIDERS = { qoyod };
export function accountingProviders() {
  return Object.keys(PROVIDERS).map((k) => ({ key: k, names: PROVIDERS[k].names }));
}

/* ============================================================
 * الارسال: الكرون كل خمس دقائق، وزر «ارسال الان» لحساب بعينه
 * ============================================================ */
export async function runAccountingPush(env, opts) {
  const o = opts || {};
  if (!env.WORKER_SECRET || !env.SUPABASE_URL) return { skipped: "not configured" };
  const started = Date.now();
  const budget = o.budgetMs || 25000;
  const secret = env.WORKER_SECRET;
  const rows = (await rpc(env, "acct_pending", { p_secret: secret, p_org: o.org || null, p_limit: o.limit || 10 })) || [];
  const summary = { orgs: 0, sent: 0, failed: 0, waiting: 0, skipped: 0 };
  if (!Array.isArray(rows) || !rows.length) return summary;

  const byOrg = new Map();
  for (const r of rows) {
    if (!byOrg.has(r.org_id)) byOrg.set(r.org_id, []);
    byOrg.get(r.org_id).push(r);
  }
  for (const [org, items] of byOrg) {
    if (Date.now() - started > budget) break;
    let link = null;
    try { link = await rpc(env, "acct_link_key", { p_secret: secret, p_org: org }); } catch { link = null; }
    const provider = link && link.key ? PROVIDERS[link.provider] : null;
    if (!provider) continue;
    summary.orgs += 1;
    const ctx = { key: link.key, settings: link.settings || {}, cache: new Map(), accounts: null };
    for (const item of items) {
      if (Date.now() - started > budget) break;
      const kind = itemKind(item);
      let claimed = false;
      try {
        claimed = await rpc(env, "acct_claim", { p_secret: secret, p_item: item.id, p_org: org, p_provider: link.provider, p_kind: kind || "none" });
      } catch { claimed = false; }
      if (claimed !== true) continue;
      let res;
      if (!kind) res = { status: "skipped" };
      else {
        try { res = await provider.push(ctx, item, kind); }
        catch (e) {
          const resp = e && e.resp;
          res = { status: "failed", error: String((e && e.message) || e).slice(0, 400), stop: authStop(resp) || rateStop(resp) };
        }
      }
      try {
        await rpc(env, "acct_mark", {
          p_secret: secret, p_item: item.id, p_provider: link.provider, p_status: res.status,
          p_external_id: res.external_id || null, p_ref: res.ref || null, p_error: res.error || null,
        });
      } catch { /* يبقى محجوزا، ويعاد بعد نصف ساعة فيجد مرجعه ولا يتكرر */ }
      summary[res.status] = (summary[res.status] || 0) + 1;
      if (res.stop) break;
    }
  }
  return summary;
}

/* ============================================================
 * مسارات /api/accounting/* : بجلسة المستخدم، والادارة للمالك والمشرف وحدهما
 * ============================================================ */
const attempts = new Map();
function tooMany(userId) {
  const now = Date.now();
  const b = attempts.get(userId);
  if (!b || now - b.start > 10 * 60 * 1000) { attempts.set(userId, { start: now, n: 1 }); return false; }
  b.n += 1;
  if (attempts.size > 2000) attempts.clear();
  return b.n > 10;
}

async function roleOf(env, org, user) {
  try { return await rpc(env, "acct_role", { p_secret: env.WORKER_SECRET, p_org: org, p_user: user.id }); }
  catch { return "none"; }
}

function cleanSettings(raw) {
  const s = raw && typeof raw === "object" ? raw : {};
  const out = {};
  for (const k of ["inventory_id", "expense_account_id", "sales_product_id", "default_vendor_id"]) {
    if (!(k in s)) continue;
    out[k] = s[k] === null || s[k] === "" ? null : posInt(s[k]);
  }
  if ("expense_tax" in s) out.expense_tax = s.expense_tax === "exempt" ? "exempt" : "inclusive15";
  return out;
}

async function connect(env, user, body) {
  const org = String(body.org || "").trim();
  const providerKey = String(body.provider || "").trim();
  const key = String(body.key || "").trim();
  const provider = PROVIDERS[providerKey];
  if (!org || !provider) return { error: "bad_request", status: 400 };
  if (!key || key.length > 400) return { error: "no_key", status: 400 };
  if ((await roleOf(env, org, user)) !== "admin") return { error: "not_admin", status: 403 };
  if (tooMany(user.id)) return { error: "rate_limited", status: 429 };
  const ok = await provider.verify(key);
  if (!ok.ok) return { error: ok.error, status: ok.error === "invalid_key" ? 400 : 502 };
  const lists = await provider.lookups(key);
  if (lists.error) return { error: lists.error, status: 502 };
  const settings = { expense_tax: "inclusive15" };
  if (lists.inventories.length === 1) settings.inventory_id = lists.inventories[0].id;
  const saved = await rpc(env, "acct_link_save", { p_secret: env.WORKER_SECRET, p_org: org, p_user: user.id, p_provider: providerKey, p_key: key, p_settings: settings });
  if (!saved || saved.status !== "saved") return { error: (saved && saved.status) || "save_failed", status: 403 };
  return { ok: true, lookups: lists };
}

async function lookups(env, user, body) {
  const org = String(body.org || "").trim();
  if (!org) return { error: "bad_request", status: 400 };
  if ((await roleOf(env, org, user)) !== "admin") return { error: "not_admin", status: 403 };
  const link = await rpc(env, "acct_link_key", { p_secret: env.WORKER_SECRET, p_org: org });
  const provider = link && link.key ? PROVIDERS[link.provider] : null;
  if (!provider) return { error: "not_connected", status: 409 };
  const lists = await provider.lookups(link.key);
  if (lists.error) return { error: lists.error, status: 502 };
  return { ok: true, lookups: lists };
}

async function saveSettings(env, user, body) {
  const org = String(body.org || "").trim();
  if (!org) return { error: "bad_request", status: 400 };
  const out = await rpc(env, "acct_link_settings", { p_secret: env.WORKER_SECRET, p_org: org, p_user: user.id, p_settings: cleanSettings(body.settings) });
  if (!out || out.status !== "saved") return { error: (out && out.status) || "save_failed", status: out && out.status === "not_connected" ? 409 : 403 };
  return { ok: true };
}

async function syncNow(env, user, body) {
  const org = String(body.org || "").trim();
  if (!org) return { error: "bad_request", status: 400 };
  if ((await roleOf(env, org, user)) !== "admin") return { error: "not_admin", status: 403 };
  if (tooMany(user.id)) return { error: "rate_limited", status: 429 };
  const summary = await runAccountingPush(env, { org, limit: 25, budgetMs: 25000 });
  return { ok: true, summary };
}

async function forget(env, user, body) {
  const org = String(body.org || "").trim();
  if (!org) return { error: "bad_request", status: 400 };
  const out = await rpc(env, "acct_link_forget", { p_secret: env.WORKER_SECRET, p_org: org, p_user: user.id });
  if (!out || out.status !== "forgotten") return { error: (out && out.status) || "failed", status: 403 };
  return { ok: true };
}

export async function handleAccounting(request, env, url, authedUser, json) {
  const routes = {
    "/api/accounting/connect": connect,
    "/api/accounting/lookups": lookups,
    "/api/accounting/settings": saveSettings,
    "/api/accounting/sync": syncNow,
    "/api/accounting/forget": forget,
  };
  const fn = routes[url.pathname];
  if (!fn || request.method !== "POST") return null;
  if (!env.WORKER_SECRET) return json({ error: "not configured" }, 503);
  const user = await authedUser(request, env);
  if (!user) return json({ error: "unauthorized" }, 401);
  let body = {};
  try { body = await request.json(); } catch { body = {}; }
  try {
    const out = await fn(env, user, body || {});
    if (out && out.error) return json({ error: out.error }, out.status || 400);
    return json(out);
  } catch (e) {
    return json({ error: "server_error" }, 500);
  }
}
