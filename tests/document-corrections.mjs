/* الورقة من المحادثة قبل حفظها: فحص الحقول بالقواعد، والتصحيح بالرد، وزر تسجيل الفاتورة مصروفا،
   ثم المسار كاملا عبر الويب هوك بقاعدة مزيفة (رد نصي يصحح المسودة، وزر المصروف يرسل as_expense).
   التشغيل: node tests/document-corrections.mjs */
import { docChecks, parseCorrection, applyCorrection, docConfirmText, docButtons } from "../src/telegram-documents.js";
import worker from "../src/worker.js";

let failed = 0;
function check(name, ok, detail) {
  if (!ok) failed++;
  console.log((ok ? "PASS " : "FAIL ") + name + (ok || detail === undefined ? "" : "\n      " + detail));
}
const show = (value) => JSON.stringify(value);
const codes = (f) => docChecks(f, "2026-10-29").map((item) => item.code).sort().join(",");

/* 1) الفحص */
check("a 10-digit CR passes", codes({ kind: "commercial_register", number: "7055060102", issue_date: "2025-01-01", expiry_date: "2027-01-01" }) === "");
check("a short CR is flagged", codes({ kind: "commercial_register", number: "705506010", expiry_date: "2027-01-01" }) === "badCr");
check("a VAT number not starting and ending with 3 is flagged", codes({ kind: "vat_certificate", number: "314983900200004" }) === "badVat");
check("expiry before issue is flagged", codes({ kind: "license", issue_date: "2026-05-01", expiry_date: "2026-01-01" }).includes("expiryBeforeIssue"));
check("an expired paper is flagged", codes({ kind: "license", issue_date: "2024-01-01", expiry_date: "2026-01-01" }) === "expired");
check("an assumed expiry is not called expired", codes({ kind: "license", issue_date: "2024-01-01", expiry_date: "2025-01-01", expiry_assumed: true }) === "");
check("an expiring paper without expiry is flagged", codes({ kind: "passport", number: "A1234567" }) === "missingExpiry");
check("a consistent invoice passes", codes({ kind: "invoice", amount: 1150, details: { subtotal: 1000, vat_amount: 150, total: 1150 } }) === "");
check("an invoice whose total does not add up is flagged", codes({ kind: "invoice", details: { subtotal: 1000, vat_amount: 150, total: 1200 } }) === "totalMismatch");
check("VAT that is not 15% is flagged", codes({ kind: "invoice", details: { subtotal: 1000, vat_amount: 100, total: 1100 } }) === "vatRate");
check("an invoice without a total is flagged", codes({ kind: "invoice", details: {} }) === "missingAmount");

/* 2) قراءة التصحيح */
const cases = [
  ["تاريخ الانتهاء خطأ، الصحيح 3-5-2027", { field: "expiry_date", value: "2027-05-03" }],
  ["الانتهاء 2027/05/03", { field: "expiry_date", value: "2027-05-03" }],
  ["تاريخ الإصدار 01-02-2026", { field: "issue_date", value: "2026-02-01" }],
  ["الرقم 7055060102", { field: "number", value: "7055060102" }],
  ["خطأ، رقم السجل 7055060102", { field: "number", value: "7055060102" }],
  ["المبلغ 1,150.50", { field: "amount", value: 1150.5 }],
  ["اسم المورد شركة النور للتجارة", { field: "seller", value: "شركة النور للتجارة" }],
  ["الاسم «مؤسسة الفجر»", { field: "party", value: "مؤسسة الفجر" }],
  ["expiry 03-05-2027", { field: "expiry_date", value: "2027-05-03" }],
  ["amount 99", { field: "amount", value: 99 }],
];
for (const [text, want] of cases) {
  const got = parseCorrection(text);
  check(`correction read: «${text}»`, got && got.field === want.field && got.value === want.value, show(got));
}
check("a question is not a correction", parseCorrection("كم مبلغ الفواتير هذا الشهر؟") === null || parseCorrection("ما هي مواعيدي") === null);
check("a date that is not a date is refused", parseCorrection("تاريخ الانتهاء قريب") === null);
const hijri = parseCorrection("الانتهاء 1448-11-17");
check("a Hijri date is converted to Gregorian", hijri && /^2027-0[45]-\d{2}$/.test(hijri.value), show(hijri));

const fixed = applyCorrection({ kind: "license", expiry_date: "2026-01-01", expiry_assumed: true, details: {} }, { field: "expiry_date", value: "2027-05-03" });
check("a corrected expiry is no longer marked assumed, and the field is remembered", fixed.expiry_date === "2027-05-03" && fixed.expiry_assumed === false && show(fixed.corrected) === '["expiry_date"]', show(fixed));

/* 3) النص والازرار */
const invoice = { kind: "invoice", number: "INV-77", amount: 1150, issue_date: "2026-10-20", details: { seller: "شركة النور", subtotal: 1000, vat_amount: 150, total: 1150 } };
const text = docConfirmText("ar", invoice);
check("the invoice summary shows the supplier and asks expense or document", /المورد: شركة النور/.test(text) && /مصروفا/.test(text) && !/⚠️/.test(text), text);
const ids = docButtons("ar", invoice).reply_markup.inline_keyboard[0].map((button) => button.callback_data).join(",");
check("an invoice offers record-as-expense, save, skip", ids === "doc:e,doc:y,doc:n", ids);
check("other papers keep save / skip", docButtons("ar", { kind: "license" }).reply_markup.inline_keyboard[0].length === 2);
check("a warning appears in the summary", /⚠️ رقم السجل التجاري 10 أرقام/.test(docConfirmText("ar", { kind: "commercial_register", number: "123", expiry_date: "2027-01-01" })));
for (const lang of ["ar", "en", "fr", "ur"]) {
  const summary = docConfirmText(lang, { kind: "invoice", details: { subtotal: 1000, vat_amount: 100, total: 1300 } });
  check(`summary (${lang}) has no internal names and no diacritics`, !/\b[a-z]+_[a-z_]+\b/.test(summary) && !/[\u064B-\u0652]/.test(summary) && !/undefined|null|NaN/.test(summary), summary);
}

/* 4) المسار كاملا في تيليغرام: ورقة تنتظر القرار ← «المبلغ 1200» ← عرض جديد ← زر المصروف */
const env = { TELEGRAM_BOT_TOKEN: "t", TELEGRAM_WEBHOOK_SECRET: "s", WORKER_SECRET: "w".repeat(40), SUPABASE_URL: "https://db.test", SUPABASE_ANON_KEY: "a" };
const sent = []; const saves = [];
const drafts = new Map([["77", { user_id: "u-1", payload: { type: "doc", doc: invoice, file: { file_id: "f1", name: "فاتورة.pdf", mime: "application/pdf", size_bytes: 9 } } }]]);
globalThis.fetch = async (input, init = {}) => {
  const url = String(input);
  const reply = (value) => new Response(value == null ? "" : JSON.stringify(value), { status: 200 });
  if (url.includes("/rest/v1/rpc/")) {
    const name = url.split("/").pop(); const args = JSON.parse(init.body || "{}");
    if (name === "log_telegram_message") return reply("u-1");
    if (name === "notify_target") return reply({ lang: "ar", full_name: "رعد" });
    if (name === "telegram_draft_take") { const draft = drafts.get(args.p_chat_id) || null; drafts.delete(args.p_chat_id); return reply(draft); }
    if (name === "telegram_draft_put") { drafts.set(args.p_chat_id, { user_id: args.p_user_id, payload: args.p_payload }); return reply(null); }
    if (name === "telegram_org_choices") return reply([{ id: "o1", name: "شركة", active: true }]);
    if (name === "telegram_save_document") { saves.push(args); return reply({ status: "expense", title: "فاتورة — شركة النور INV-77", amount: args.p_doc.amount }); }
    return reply(null);
  }
  if (url.includes("api.telegram.org")) { if (url.endsWith("/sendMessage")) sent.push(JSON.parse(init.body)); return reply({ ok: true }); }
  throw new Error("unexpected " + url);
};
const post = (update) => worker.fetch(new Request("https://mrzahi.com/api/telegram/webhook", { method: "POST", body: JSON.stringify(update), headers: { "x-telegram-bot-api-secret-token": "s" } }), env, {});
await post({ message: { chat: { id: 77, type: "private" }, from: { id: 77, first_name: "R" }, text: "المبلغ 1200" } });
const again = sent.pop();
check("a reply correction re-shows the summary with the new amount and the same buttons",
  again && /✏️ عدلت: المبلغ ← 1200/.test(again.text) && /⚠️/.test(again.text) && again.reply_markup.inline_keyboard[0][0].callback_data === "doc:e", show(again && again.text));
check("the draft keeps the correction", drafts.get("77") && drafts.get("77").payload.doc.amount === 1200 && drafts.get("77").payload.doc.details.total === 1200);
await post({ callback_query: { id: "c", data: "doc:e", from: { id: 77 }, message: { chat: { id: 77, type: "private" }, message_id: 5 } } });
const saved = saves.pop();
check("the expense button saves with as_expense and the corrected fields", saved && saved.p_doc.as_expense === true && show(saved.p_doc.corrected) === '["amount"]', show(saved && saved.p_doc));
const done = sent.pop();
check("the reply says it was recorded in Expenses with a button to open them", done && /سجلت في المصاريف/.test(done.text) && /type=expenses/.test(show(done.reply_markup)), show(done));
await post({ message: { chat: { id: 77, type: "private" }, from: { id: 77, first_name: "R" }, text: "المبلغ 5" } });
check("with no paper waiting, «المبلغ 5» is not treated as a correction", !sent.some((message) => /✏️/.test(message.text || "")));

console.log(failed ? `\n${failed} failed` : "\nall correction checks pass");
process.exit(failed ? 1 : 0);
