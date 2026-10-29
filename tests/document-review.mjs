/* اكمال مرونة الادخال من المحادثة: السؤال عن الناقص، والتنبيه على المكرر، والتراجع، والمراجعة، وملف الموظف،
   عبر الويب هوك بقاعدة مزيفة. التشغيل: node tests/document-review.mjs */
import worker from "../src/worker.js";

let failed = 0;
function check(name, ok, detail) {
  if (!ok) failed++;
  console.log((ok ? "PASS " : "FAIL ") + name + (ok || detail === undefined ? "" : "\n      " + detail));
}
const show = (value) => JSON.stringify(value);
const ITEM = "11111111-2222-3333-4444-555555555555";

const env = { TELEGRAM_BOT_TOKEN: "t", TELEGRAM_WEBHOOK_SECRET: "s", WORKER_SECRET: "w".repeat(40), SUPABASE_URL: "https://db.test", SUPABASE_ANON_KEY: "a" };
let sent = []; const calls = []; const drafts = new Map();
let saveReply = () => ({ status: "created", kind: "license", item_id: ITEM, undoable: true });
let precheck = { similar: null, can_hr: false };
const rpcReplies = {
  log_telegram_message: () => "u-1",
  notify_target: () => ({ lang: "ar", full_name: "سالم" }),
  telegram_org_choices: () => [{ id: "o1", name: "شركة", active: true }],
  telegram_draft_take: (args) => { const draft = drafts.get(args.p_chat_id) || null; drafts.delete(args.p_chat_id); return draft; },
  telegram_draft_put: (args) => { drafts.set(args.p_chat_id, { user_id: args.p_user_id, payload: args.p_payload }); return null; },
  chat_document_precheck: () => precheck,
  telegram_save_document: (args) => saveReply(args),
  chat_review_targets: () => [{ chat_id: "900", lang: "ar" }],
  chat_undo_save: () => ({ status: "ok", title: "الرخصة" }),
  chat_review_approve: () => ({ status: "ok", title: "الرخصة" }),
  chat_review_list: () => [{ id: ITEM, title: "فاتورة — شركة النور", date: "2026-10-29", by: "سالم", reasons: ["vatRate", "corrected"] }],
};
globalThis.fetch = async (input, init = {}) => {
  const url = String(input);
  const reply = (value) => new Response(value == null ? "" : JSON.stringify(value), { status: 200 });
  if (url.includes("/rest/v1/rpc/")) {
    const name = url.split("/").pop(); const args = JSON.parse(init.body || "{}");
    calls.push({ name, args });
    return reply(rpcReplies[name] ? rpcReplies[name](args) : null);
  }
  if (url.includes("api.telegram.org")) {
    if (url.endsWith("/sendMessage")) sent.push(JSON.parse(init.body));
    if (url.includes("/getFile")) return reply({ ok: true, result: { file_path: "doc.pdf", file_size: 9 } });
    if (url.includes("/file/bot")) return new Response("%PDF-test", { status: 200 });
    return reply({ ok: true });
  }
  throw new Error("unexpected " + url);
};
const text = (body) => worker.fetch(new Request("https://mrzahi.com/api/telegram/webhook", { method: "POST",
  body: JSON.stringify({ message: { chat: { id: 77, type: "private" }, from: { id: 77, first_name: "R" }, text: body } }),
  headers: { "x-telegram-bot-api-secret-token": "s" } }), env, {});
const press = (data) => worker.fetch(new Request("https://mrzahi.com/api/telegram/webhook", { method: "POST",
  body: JSON.stringify({ callback_query: { id: "c", data, from: { id: 77 }, message: { chat: { id: 77, type: "private" }, message_id: 5 } } }),
  headers: { "x-telegram-bot-api-secret-token": "s" } }), env, {});
const paper = (doc, canHr) => drafts.set("77", { user_id: "u-1", payload: { type: "doc", doc, file: { file_id: "f1", name: "ورقة.pdf", mime: "application/pdf", size_bytes: 9 }, canHr } });
const last = () => sent[sent.length - 1] || {};
const buttonIds = (message) => ((message.reply_markup && message.reply_markup.inline_keyboard) || []).flat().map((button) => button.callback_data || button.url);
const lastSave = () => calls.filter((call) => call.name === "telegram_save_document").pop();

/* 1) السؤال عن الناقص */
paper({ kind: "invoice", number: "INV-1", details: { seller: "شركة النور" } });
await press("doc:e");
check("an expense without a total asks for the amount instead of saving", /ما المبلغ الإجمالي/.test(last().text) && !lastSave() && drafts.get("77").payload.awaiting === "amount", show(last().text));
await text("1150");
check("a bare number answers the question and re-shows the summary", /✏️ عدلت: المبلغ ← 1150/.test(last().text) && drafts.get("77").payload.doc.amount === 1150 && !drafts.get("77").payload.awaiting, show(last().text));
saveReply = (args) => ({ status: "expense", title: "فاتورة — شركة النور INV-1", amount: args.p_doc.amount, item_id: ITEM, undoable: true });
await press("doc:e");
check("then the expense is saved with the given amount", lastSave() && lastSave().args.p_doc.amount === 1150 && lastSave().args.p_doc.as_expense === true);
check("the saved reply carries an undo button", buttonIds(last()).includes("undo:" + ITEM), show(buttonIds(last())));

paper({ kind: "passport", number: "A1234567", party: "محمد" });
saveReply = () => ({ status: "created", kind: "passport", item_id: ITEM, undoable: true });
const savesBefore = calls.filter((call) => call.name === "telegram_save_document").length;
await press("doc:y");
check("a passport without expiry asks once", /لم أجد تاريخ الانتهاء/.test(last().text) && calls.filter((call) => call.name === "telegram_save_document").length === savesBefore);
await press("doc:y");
check("pressing save again saves without it", calls.filter((call) => call.name === "telegram_save_document").length === savesBefore + 1, show(last().text));
check("a bare number with no question pending is not taken as a correction", (await text("1150"), !/✏️/.test(last().text)));

/* 2) التنبيه على المكرر */
precheck = { similar: { title: "فاتورة — شركة النور INV-1", date: "2026-10-28" }, can_hr: false };
const { offerDocument } = await import("../src/telegram-documents.js");
await offerDocument(env, { chatId: 77, userId: "u-1", lang: "ar", text: "فاتورة ضريبية\nرقم الفاتورة INV-1\nالمورد شركة النور\nالإجمالي 1150", file: { file_id: "f2", name: "inv.pdf", mime: "application/pdf", size_bytes: 9 } });
check("a paper like a recorded one is flagged in the summary", /⚠️ تشبه «فاتورة — شركة النور INV-1» المسجلة في 28-10-2026/.test(last().text), show(last().text));

/* 3) التراجع */
await press("undo:" + ITEM);
check("undo cancels and says the item stays recoverable", /ألغي، ويبقى في السجل للاسترجاع/.test(last().text) && calls.some((call) => call.name === "chat_undo_save" && call.args.p_item_id === ITEM));

/* 4) المراجعة */
sent = [];
paper({ kind: "invoice", number: "INV-2", amount: 1100, details: { seller: "س", subtotal: 1000, vat_amount: 100, total: 1100 } });
saveReply = () => ({ status: "expense", title: "فاتورة — س INV-2", amount: 1100, item_id: ITEM, undoable: true, needs_review: true });
await press("doc:e");
const reasons = lastSave().args.p_doc.review;
check("the save carries the review reasons", show(reasons) === '["vatRate"]', show(reasons));
const notice = sent.find((message) => String(message.chat_id) === "900");
check("the manager gets a review notice with an approve button", notice && /📋 يحتاج مراجعة/.test(notice.text) && /أدخله: سالم/.test(notice.text) && /نسبة الضريبة/.test(notice.text) && buttonIds(notice).includes("rv:" + ITEM), show(notice));
check("the employee is told it went to the manager", sent.some((message) => String(message.chat_id) === "77" && /وأرسل إلى المدير للمراجعة/.test(message.text)));
await press("rv:" + ITEM);
check("approve answers with the title", /اعتمد: الرخصة/.test(last().text));
await text("المراجعة");
check("«المراجعة» lists what waits, with reasons and an approve button", /تنتظر المراجعة/.test(last().text) && /صححها المرسل/.test(last().text) && buttonIds(last()).includes("rv:" + ITEM), show(last()));

/* 5) ملف الموظف */
paper({ kind: "id_document", number: "2123456789", party: "محمد أحمد", expiry_date: "2027-03-01" }, false);
await press("doc:s");
check("no employee file for someone outside HR", /ملفات الموظفين لقسم الموارد البشرية/.test(last().text) && drafts.has("77"));
paper({ kind: "employment_contract", details: { job_title: "محاسب" } }, true);
await press("doc:s");
check("an employee file without a name asks for it", /لم أجد اسم الموظف/.test(last().text) && drafts.get("77").payload.awaiting === "party");
await text("الاسم محمد أحمد");
check("the name is taken from the reply", drafts.get("77").payload.doc.party === "محمد أحمد", show(drafts.get("77").payload.doc));
check("the summary now offers the employee file button", buttonIds(last())[0] === "doc:s", show(buttonIds(last())));
saveReply = (args) => ({ status: "staff", title: args.p_doc.party, item_id: ITEM, undoable: true });
await press("doc:s");
check("the employee file is saved with as_staff", lastSave().args.p_doc.as_staff === true && /أنشئ ملف الموظف: محمد أحمد/.test(last().text) && buttonIds(last()).includes("undo:" + ITEM), show(last()));

console.log(failed ? `\n${failed} failed` : "\nall review checks pass");
process.exit(failed ? 1 : 0);
