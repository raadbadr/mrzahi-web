// معيار Google Drive من الخادم: يمر يوميا على كل الحسابات المرتبطة ويطبق المعيار نفسه الذي يطبقه
// المتصفح في app/common/part.2.js، كي لا يبقى مجلد قديم لمن لم يفتح الموقع (امر المهندس رعد 2026-09-11،
// «دا راح يكون ستاندرد مستر زاهي ومافي اي تنازل»). المعيار: جذر واحد 00-MrZahi ازرق، وتحته مجلد
// الشركة باسمها موسوما mrzahi_org وبنفس اللون، ولا انشاء مع وجود سابق، ودمج المكرر في الاكثر ملفات.
import { rpc } from "./notify.js";

const API = "https://www.googleapis.com/drive/v3/files";
const TOKEN = "https://oauth2.googleapis.com/token";
const FOLDER = "application/vnd.google-apps.folder";
export const DRIVE_ROOT_NAME = "00-MrZahi";
export const DRIVE_LEGACY_ROOT_NAMES = ["MrZahi", "TheTracker"];
export const DRIVE_FOLDER_COLOR = "#4986e7";

const esc = (v) => String(v || "").replace(/\\/g, "\\\\").replace(/'/g, "\\'");

async function accessToken(env, refresh) {
  const res = await fetch(TOKEN, {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: env.GOOGLE_CLIENT_ID, client_secret: env.GOOGLE_CLIENT_SECRET, refresh_token: refresh, grant_type: "refresh_token" }),
  });
  const j = await res.json().catch(() => ({}));
  if (!res.ok || !j.access_token) throw new Error("token " + res.status + " " + (j.error || ""));
  return j.access_token;
}

async function g(token, url, init) {
  const res = await fetch(url, { ...(init || {}), headers: { Authorization: "Bearer " + token, ...((init && init.headers) || {}) } });
  if (res.status === 204) return null;
  const j = await res.json().catch(() => null);
  if (!res.ok) { const e = new Error("drive " + res.status); e.status = res.status; e.data = j; throw e; }
  return j;
}
const list = (token, q, fields, n) => g(token, `${API}?q=${encodeURIComponent(q)}&fields=files(${fields || "id,name"})&pageSize=${n || 50}&spaces=drive`).then((d) => (d && d.files) || []);
const patch = (token, id, body) => g(token, `${API}/${encodeURIComponent(id)}?fields=id`, { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
const create = (token, meta) => g(token, `${API}?fields=id`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(meta) }).then((f) => f.id);
const countChildren = (token, id) => list(token, `'${esc(id)}' in parents and trashed=false`, "id", 1000).then((f) => f.length);

/* الجذر: الحالي ان وجد (يلون ان لزم)، والا القديم يعاد تسميته ويلون، والا ينشا */
async function ensureRoot(token, changes) {
  const base = `mimeType='${FOLDER}' and trashed=false and 'root' in parents and name='`;
  let cur = await list(token, base + esc(DRIVE_ROOT_NAME) + "'", "id,name,folderColorRgb", 5);
  if (!cur.length) {
    for (const legacy of DRIVE_LEGACY_ROOT_NAMES) {
      const old = await list(token, base + esc(legacy) + "'", "id,name,folderColorRgb", 5);
      if (old.length) { await patch(token, old[0].id, { name: DRIVE_ROOT_NAME, folderColorRgb: DRIVE_FOLDER_COLOR }); changes.push("root renamed from " + legacy); return old[0].id; }
    }
    const id = await create(token, { name: DRIVE_ROOT_NAME, mimeType: FOLDER, parents: ["root"], folderColorRgb: DRIVE_FOLDER_COLOR });
    changes.push("root created"); return id;
  }
  if (String(cur[0].folderColorRgb || "").toLowerCase() !== DRIVE_FOLDER_COLOR) { await patch(token, cur[0].id, { folderColorRgb: DRIVE_FOLDER_COLOR }); changes.push("root colored"); }
  // جذور مكررة بالاسم نفسه: تدمج في الاول
  for (const extra of cur.slice(1)) { await moveChildren(token, extra.id, cur[0].id); if ((await countChildren(token, extra.id)) === 0) { await patch(token, extra.id, { trashed: true }); changes.push("duplicate root trashed"); } }
  return cur[0].id;
}

async function moveChildren(token, from, to) {
  const kids = await list(token, `'${esc(from)}' in parents and trashed=false`, "id", 1000);
  for (const k of kids) { try { await g(token, `${API}/${encodeURIComponent(k.id)}?addParents=${encodeURIComponent(to)}&removeParents=${encodeURIComponent(from)}&fields=id`, { method: "PATCH" }); } catch {} }
  return kids.length;
}

/* مجلد الشركة: المرشحون من مرفقات سابقة والوسمين والاسم تحت الجذر؛ الفائز الاكثر ملفات؛ الباقي يدمج فيه */
async function ensureOrgFolder(token, rootId, row, changes) {
  const orgId = row.org_id, name = row.org_name || "Company";
  const cands = new Map(); // id -> anchored?
  for (const fid of (row.file_ids || []).slice(0, 5)) {
    try { const f = await g(token, `${API}/${encodeURIComponent(fid)}?fields=parents,trashed`); const p = f && !f.trashed && f.parents && f.parents[0]; if (!p) continue;
      const d = await g(token, `${API}/${encodeURIComponent(p)}?fields=id,trashed,mimeType`); if (d && !d.trashed && d.mimeType === FOLDER) cands.set(d.id, true); } catch {}
  }
  const base = `mimeType='${FOLDER}' and trashed=false`;
  for (const key of ["mrzahi_org", "tracker_org"]) for (const f of await list(token, `${base} and appProperties has { key='${key}' and value='${esc(orgId)}' }`, "id", 20)) if (!cands.has(f.id)) cands.set(f.id, false);
  const roots = [rootId];
  for (const legacy of DRIVE_LEGACY_ROOT_NAMES) for (const r of await list(token, `${base} and 'root' in parents and name='${esc(legacy)}'`, "id", 5)) roots.push(r.id);
  for (const r of roots) for (const f of await list(token, `${base} and name='${esc(name)}' and '${esc(r)}' in parents`, "id", 20)) if (!cands.has(f.id)) cands.set(f.id, false);

  let best = null;
  if (cands.size) {
    const scored = [];
    for (const [id, anchored] of cands) scored.push({ id, n: await countChildren(token, id).catch(() => -1), anchored });
    scored.sort((a, b) => (b.n + (b.anchored ? 0.5 : 0)) - (a.n + (a.anchored ? 0.5 : 0)));
    best = scored[0].id;
    for (const o of scored.slice(1)) {
      if (o.n < 0) continue;
      const moved = await moveChildren(token, o.id, best); if (moved) changes.push(`moved ${moved} from duplicate`);
      if ((await countChildren(token, o.id).catch(() => 1)) === 0) { await patch(token, o.id, { trashed: true }); changes.push("duplicate org folder trashed"); }
    }
  } else {
    best = await create(token, { name, mimeType: FOLDER, parents: [rootId], appProperties: { mrzahi_org: orgId }, folderColorRgb: DRIVE_FOLDER_COLOR });
    changes.push("org folder created");
  }
  // الفائز: تحت الجذر، بالوسم الحالي، باللون، وبالاسم الحالي للشركة
  const f = await g(token, `${API}/${encodeURIComponent(best)}?fields=id,name,parents,appProperties,folderColorRgb`);
  const body = {};
  if (!(f.appProperties && f.appProperties.mrzahi_org === orgId)) body.appProperties = { mrzahi_org: orgId, tracker_org: null };
  if (String(f.folderColorRgb || "").toLowerCase() !== DRIVE_FOLDER_COLOR) body.folderColorRgb = DRIVE_FOLDER_COLOR;
  if (f.name !== name) body.name = name;
  if (Object.keys(body).length) { await patch(token, best, body); changes.push("org folder standardized"); }
  const parent = f.parents && f.parents[0];
  if (parent && parent !== rootId) { try { await g(token, `${API}/${encodeURIComponent(best)}?addParents=${encodeURIComponent(rootId)}&removeParents=${encodeURIComponent(parent)}&fields=id`, { method: "PATCH" }); changes.push("org folder moved under root"); } catch {} }
  // جذور قديمة صارت فارغة بعد النقل
  for (const r of roots.slice(1)) { if ((await countChildren(token, r).catch(() => 1)) === 0) { try { await patch(token, r, { trashed: true }); changes.push("empty legacy root trashed"); } catch {} } }
  return best;
}

export async function driveStandardSweep(env) {
  if (!env.GOOGLE_CLIENT_ID || !env.GOOGLE_CLIENT_SECRET || !env.WORKER_SECRET) return { skipped: "not configured" };
  const rows = (await rpc(env, "drive_conn_sweep_list", { p_secret: env.WORKER_SECRET })) || [];
  const out = [];
  for (const row of rows) {
    const changes = [];
    try {
      const token = await accessToken(env, row.refresh_token);
      const rootId = await ensureRoot(token, changes);
      const folderId = await ensureOrgFolder(token, rootId, row, changes);
      out.push({ org: row.org_id, folder: folderId, changes });
    } catch (e) { out.push({ org: row.org_id, error: String((e && e.message) || e).slice(0, 160) }); }
  }
  return { orgs: rows.length, results: out };
}
