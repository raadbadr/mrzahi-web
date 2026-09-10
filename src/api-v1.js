/* /api/v1 بمفتاح API (mz_live_…): تصدير CSV/JSON، استيراد صفوف، وتوثيق خادم MCP.
   نقل من worker.js كي يبقى كل ملف تحت ألف سطر. */
import * as XLSX from "xlsx";
import { rpc } from "./notify.js";
import { ALLOWED_EXT, fileExt, parseWorkbook, draftPayload } from "./telegram-import.js";

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}
export async function sha256Hex(text) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
function v1Json(data, status = 200) {
  const r = json(data, status);
  r.headers.set("Access-Control-Allow-Origin", "*");
  return r;
}
async function v1Auth(request, env) {
  if (!env.WORKER_SECRET) return { error: v1Json({ error: "not configured" }, 503) };
  const m = (request.headers.get("Authorization") || "").match(/^Bearer\s+(mz_live_[a-f0-9]{48})$/i);
  if (!m) return { error: v1Json({ error: "missing or malformed API key" }, 401) };
  const hash = await sha256Hex(m[1]);
  let who = null;
  try { who = await rpc(env, "api_key_resolve", { p_secret: env.WORKER_SECRET, p_hash: hash }); } catch { who = null; }
  if (!who || !who.org_id) return { error: v1Json({ error: "invalid or revoked API key" }, 401) };
  return { hash, who };
}
function csvOf(rows) {
  const keys = ["number", "title", "category", "record", "status", "due_at", "assignee_email", "amount", "client_name", "case_number", "created_at"];
  const extra = new Set();
  rows.forEach((r) => Object.keys(r.data || {}).forEach((k) => extra.add(k)));
  const cols = keys.concat([...extra]);
  const q = (v) => '"' + String(v === null || v === undefined ? "" : (typeof v === "object" ? JSON.stringify(v) : v)).replace(/"/g, '""') + '"';
  const lines = [cols.map(q).join(",")];
  rows.forEach((r) => lines.push(cols.map((c) => q(c in r ? r[c] : (r.data || {})[c])).join(",")));
  return "\ufeff" + lines.join("\r\n");
}
function rowsToCsvBytes(rows, recordName) {
  const ws = XLSX.utils.json_to_sheet(rows.map((r) => (r && typeof r === "object") ? r : { title: String(r) }));
  const wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, ws, recordName || "data");
  return XLSX.write(wb, { type: "array", bookType: "csv" });
}
/* استيراد صفوف JSON بمفتاح API (يستعمله /api/v1/import وخادم MCP) */
export async function importRowsWithKey(env, hash, rows, recordName) {
  if (!Array.isArray(rows) || !rows.length) return { ok: false, error: "no rows" };
  const filename = (recordName || "api") + ".csv";
  let parsed;
  try { parsed = parseWorkbook(rowsToCsvBytes(rows.slice(0, 500), recordName), filename); } catch (e) { console.log("api import parse failed", String(e.message || e).slice(0, 120)); return { ok: false, error: "cannot_parse" }; }
  const payload = draftPayload(parsed);
  const results = [], errors = [];
  for (const sh of payload.sheets) {
    try {
      results.push(await rpc(env, "api_import", { p_secret: env.WORKER_SECRET, p_hash: hash, p_filename: filename,
        p_record_name: recordName || sh.record || sh.name, p_columns: sh.columns || [], p_mapping: sh.mapping || {}, p_rows: sh.rows || [] }));
    } catch (e) { console.log("api import sheet failed", sh.name, String(e.message || e).slice(0, 200)); errors.push({ sheet: sh.name, message: "import_failed" }); }
  }
  const imported = results.reduce((n, r) => n + (Number(r && (r.inserted ?? r.imported ?? r.count)) || 0), 0);
  return { ok: errors.length === 0, imported, results, errors };
}
export async function mcpAuthenticate(request, env) {
  const a = await v1Auth(request, env);
  if (a.error) return { error: true, status: a.error.status, message: a.error.status === 503 ? "not configured" : "invalid or missing API key (Authorization: Bearer mz_live_…)" };
  return a;
}
export async function handleV1(request, env, url) {
  const path = url.pathname;
  const auth = await v1Auth(request, env);
  if (auth.error) return auth.error;
  const { hash, who } = auth;

  if (path === "/api/v1/ping") return v1Json({ ok: true, org: who.org_name });

  if (path === "/api/v1/items" && request.method === "GET") {
    const record = url.searchParams.get("record") || null;
    let rows = [];
    try { rows = (await rpc(env, "api_items_export", { p_secret: env.WORKER_SECRET, p_hash: hash, p_record: record })) || []; }
    catch (e) { console.log("v1 export failed", String(e.message || e).slice(0, 200)); return v1Json({ error: "export_failed" }, 500); }
    if ((url.searchParams.get("format") || "").toLowerCase() === "csv") {
      return new Response(csvOf(rows), { headers: { "Content-Type": "text/csv; charset=utf-8", "Content-Disposition": "attachment; filename=items.csv", "Access-Control-Allow-Origin": "*", "Cache-Control": "no-store" } });
    }
    return v1Json({ count: rows.length, items: rows });
  }

  if (path === "/api/v1/import" && request.method === "POST") {
    const ct = (request.headers.get("Content-Type") || "").toLowerCase();
    let bytes = null, filename = "api.csv", recordName = url.searchParams.get("record") || null;
    try {
      if (ct.includes("multipart/form-data")) {
        const form = await request.formData();
        const f = form.get("file");
        if (!f || typeof f.arrayBuffer !== "function") return v1Json({ error: "file field missing" }, 400);
        recordName = recordName || form.get("record") || null;
        filename = f.name || filename; bytes = await f.arrayBuffer();
      } else if (ct.includes("application/json") || ct.includes("text/json")) {
        const body = await request.json();
        const rows = Array.isArray(body) ? body : (body.rows || body.items || body.data || []);
        if (!Array.isArray(rows) || !rows.length) return v1Json({ error: "no rows" }, 400);
        recordName = recordName || body.record || null;
        bytes = rowsToCsvBytes(rows, recordName); filename = (recordName || "api") + ".csv";
      } else {
        bytes = await request.arrayBuffer(); filename = (recordName || "api") + (ct.includes("spreadsheet") || ct.includes("excel") ? ".xlsx" : ".csv");
      }
    } catch (e) { console.log("v1 unreadable body", String(e.message || e).slice(0, 120)); return v1Json({ error: "unreadable_body" }, 400); }
    if (!ALLOWED_EXT.includes(fileExt(filename))) return v1Json({ error: "unsupported file type" }, 415);

    let parsed;
    try { parsed = parseWorkbook(bytes, filename); } catch (e) { console.log("v1 parse failed", String(e.message || e).slice(0, 120)); return v1Json({ error: "cannot_parse" }, 422); }
    const payload = draftPayload(parsed);
    const results = [], errors = [];
    for (const sh of payload.sheets) {
      try {
        results.push(await rpc(env, "api_import", {
          p_secret: env.WORKER_SECRET, p_hash: hash, p_filename: filename,
          p_record_name: recordName || sh.record || sh.name, p_columns: sh.columns || [], p_mapping: sh.mapping || {}, p_rows: sh.rows || [],
        }));
      } catch (e) { console.log("v1 import sheet failed", sh.name, String(e.message || e).slice(0, 200)); errors.push({ sheet: sh.name, message: "import_failed" }); }
    }
    return v1Json({ ok: errors.length === 0, results, errors, unusable: (parsed.unusable || []).map((u) => ({ sheet: u.name, rows: u.skipped })) }, errors.length && !results.length ? 422 : 200);
  }
  return v1Json({ error: "not found" }, 404);
}

/** POST /api/notify/test { channel } — رسالة تجريبية لقناة المستخدم الحالي */
