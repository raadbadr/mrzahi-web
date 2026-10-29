/* قناة WhatsApp: تحويل ازرار تيليغرام الى رسائل WhatsApp، ثم مسار الويب هوك كاملا بقاعدة وMeta مزيفتين
   (التوقيع، الربط بالرقم بعد تاكيد صاحبه، القائمة، زر من القائمة، المستند ونسخه الى خادم جدة).
   التشغيل: node tests/whatsapp-channel.mjs */
import crypto from "crypto";
import { whatsappMessages } from "../src/whatsapp.js";
import { actionButtons, menuKeyboard, menuAction, urlButton, contactKeyboard } from "../src/notify.js";
import worker from "../src/worker.js";

let failed = 0;
function check(name, ok, detail) {
  if (!ok) failed++;
  console.log((ok ? "PASS " : "FAIL ") + name + (ok || detail === undefined ? "" : "\n      " + detail));
}
const show = (value) => JSON.stringify(value);

/* 1) التحويل */
const confirm = whatsappMessages("سيضاف: جلسة القضية 4521", actionButtons("ar", "a1b2c3"), menuAction);
check("two confirm buttons become reply buttons with the draft token", confirm.length === 1 && confirm[0].interactive.type === "button"
  && confirm[0].interactive.action.buttons.map((button) => button.reply.id).join(",") === "act:y:a1b2c3,act:n:a1b2c3", show(confirm));

const orgs = { reply_markup: { inline_keyboard: [1, 2, 3, 4, 5].map((index) => [{ text: index === 5 ? "شركة الاعمال المتقدمة للمقاولات العامة" : "شركة " + index, callback_data: "org:" + index }]) } };
const orgList = whatsappMessages("أي شركة نتكلم عنها؟", orgs, menuAction)[0];
const rows = orgList.interactive.action.sections[0].rows;
check("five companies become a list", orgList.interactive.type === "list" && rows.length === 5, show(orgList));
check("a long company name is kept whole in the row description", rows[4].title === "5" && rows[4].description === "شركة الاعمال المتقدمة للمقاولات العامة", show(rows[4]));
check("the list button is in the message language", orgList.interactive.action.button === "اختر", orgList.interactive.action.button);

const link = whatsappMessages("لوحة التحكم", urlButton("لوحة التحكم", "https://mrzahi.com/app/dashboard.html"), menuAction)[0];
check("one link becomes a link button", link.interactive && link.interactive.type === "cta_url" && link.interactive.action.parameters.url === "https://mrzahi.com/app/dashboard.html", show(link));

const menu = whatsappMessages("اختر من الأزرار:", menuKeyboard("ar"), menuAction)[0];
const menuIds = menu.interactive && menu.interactive.action.sections[0].rows.map((row) => row.id);
check("the Telegram keyboard becomes a menu list", menu.interactive && menu.interactive.type === "list" && menuIds.join(",") === "menu:company,menu:dashboard,menu:upcoming,menu:overdue", show(menuIds));

const long = whatsappMessages("سطر\n".repeat(1500), menuKeyboard("ar"), menuAction);
check("a long reply is split into text messages and keeps every line", long.every((message) => message.type === "text") && long.map((message) => message.text.body).join("\n").split("سطر").length - 1 === 1500, long.length);
const longChoice = whatsappMessages("ا".repeat(1500), actionButtons("ar", "ff"), menuAction);
check("a long text with buttons: text first, then the buttons", longChoice.length === 2 && longChoice[0].type === "text" && longChoice[1].interactive.type === "button", show(longChoice.map((message) => message.type)));
check("the phone-share keyboard is dropped (WhatsApp already knows the number)", whatsappMessages("شارك رقمك", contactKeyboard("ar"), menuAction)[0].type === "text");

/* 2) الويب هوك */
const env = {
  WHATSAPP_APP_SECRET: "app-secret-for-test", WHATSAPP_VERIFY_TOKEN: "verify-token", WHATSAPP_TOKEN: "token", WHATSAPP_PHONE_ID: "111",
  WORKER_SECRET: "w".repeat(40), SUPABASE_URL: "https://db.test", SUPABASE_ANON_KEY: "anon",
};
const sent = [];
const rpcCalls = [];
const uploads = [];
const drafts = new Map();
let linked = null;
const rpcReplies = {
  log_telegram_message: (args) => (linked && args.p_chat_id === "wa:966500000001" ? linked : null),
  whatsapp_phone_match: () => ({ user_id: "u-1", name: "رعد", org_name: "شركة التجربة", org_personal: false }),
  telegram_draft_put: (args) => { drafts.set(args.p_chat_id, { user_id: args.p_user_id, payload: args.p_payload }); return null; },
  telegram_draft_take: (args) => { const draft = drafts.get(args.p_chat_id) || null; drafts.delete(args.p_chat_id); return draft; },
  link_channel_direct: (args) => { linked = args.p_user_id; return null; },
  notify_target: () => ({ lang: "ar", full_name: "رعد", org_name: "شركة التجربة", tz: "Asia/Riyadh" }),
  platform_admin_chats: () => [],
  telegram_items: () => [{ title: "جلسة القضية 4521", due_at: "2026-11-02T07:00:00Z" }],
  chat_upload_slot: () => ({ status: "ok", path: "org-1/2026/chat/slot.pdf" }),
  telegram_save_document: (args) => ({ status: "created", kind: args.p_doc.kind, number: args.p_doc.number, role: "owner", profile_updates: {} }),
};
globalThis.fetch = async (input, init = {}) => {
  const url = String(input);
  const json = (value) => new Response(value === null ? "" : JSON.stringify(value), { status: 200, headers: { "Content-Type": "application/json" } });
  if (url.startsWith("https://db.test/rest/v1/rpc/")) {
    const name = url.split("/").pop();
    const args = JSON.parse(init.body || "{}");
    rpcCalls.push({ name, args });
    return json(rpcReplies[name] ? rpcReplies[name](args) : null);
  }
  if (url.startsWith("https://db.test/storage/v1/object/attachments/")) { uploads.push({ url, type: init.headers["Content-Type"] }); return json({ Key: "ok" }); }
  if (url === "https://graph.facebook.com/v21.0/111/messages") {
    const body = JSON.parse(init.body);
    if (body.message_id) return json({ success: true });
    sent.push(body);
    return json({ messages: [{ id: "out" }] });
  }
  if (url === "https://graph.facebook.com/v21.0/media-1") return json({ url: "https://lookaside.test/media-1", mime_type: "application/pdf", file_size: 9 });
  if (url === "https://lookaside.test/media-1") return new Response("%PDF-test", { status: 200 });
  throw new Error("unexpected fetch " + url);
};

const sign = (raw) => "sha256=" + crypto.createHmac("sha256", env.WHATSAPP_APP_SECRET).update(raw).digest("hex");
let messageCounter = 0;
async function deliver(message, signature) {
  messageCounter += 1;
  const raw = JSON.stringify({ entry: [{ changes: [{ value: { metadata: { phone_number_id: "111" },
    contacts: [{ wa_id: "966500000001", profile: { name: "Raad" } }],
    messages: [{ id: "wamid." + messageCounter, from: "966500000001", ...message }] } }] }] });
  const pending = [];
  const ctx = { waitUntil: (promise) => pending.push(promise) };
  const res = await worker.fetch(new Request("https://mrzahi.com/api/whatsapp/webhook", { method: "POST", body: raw,
    headers: { "x-hub-signature-256": signature || sign(raw) } }), env, ctx);
  await Promise.all(pending);
  return res;
}

const verify = await worker.fetch(new Request("https://mrzahi.com/api/whatsapp/webhook?hub.mode=subscribe&hub.verify_token=verify-token&hub.challenge=42"), env, {});
check("Meta verification returns the challenge", verify.status === 200 && (await verify.text()) === "42");
const forged = await deliver({ type: "text", text: { body: "مرحبا" } }, "sha256=00");
check("a body without Meta's signature is refused", forged.status === 401 && sent.length === 0, forged.status);

await deliver({ type: "text", text: { body: "مرحبا" } });
const ask = sent.pop();
check("an unlinked number that matches one profile is asked to confirm, with the account name",
  ask && ask.interactive && ask.interactive.type === "button" && /رعد/.test(ask.interactive.body.text)
  && ask.interactive.action.buttons.map((button) => button.reply.id).join(",") === "wl:y,wl:n", show(ask));
check("nothing is linked before the confirmation", linked === null);

await deliver({ type: "interactive", interactive: { type: "button_reply", button_reply: { id: "wl:y", title: "نعم، اربطه" } } });
const linkCall = rpcCalls.find((call) => call.name === "link_channel_direct");
check("confirming links the WhatsApp number to that account", linkCall && linkCall.args.p_channel === "whatsapp" && linkCall.args.p_external_id === "966500000001" && linked === "u-1", show(linkCall));
const greeting = sent.pop();
check("the greeting comes with the menu list", greeting && greeting.interactive && greeting.interactive.type === "list" && /رعد/.test(greeting.interactive.body.text), show(greeting));

await deliver({ type: "text", text: { body: "القائمة" } });
const menuMessage = sent.pop();
check("«القائمة» shows the menu", menuMessage && menuMessage.interactive && menuMessage.interactive.type === "list", show(menuMessage));

await deliver({ type: "interactive", interactive: { type: "list_reply", list_reply: { id: "menu:upcoming", title: "مواعيدي" } } });
const upcoming = sent.pop();
const upcomingText = upcoming && (upcoming.text ? upcoming.text.body : upcoming.interactive.body.text);
check("a menu choice runs the same action as the Telegram button", /جلسة القضية 4521/.test(upcomingText || "") && /02-11-2026/.test(upcomingText || ""), show(upcoming));

/* مستند: يقرا بالقارئ بلا نموذج (نص مزيف عبر env.AI)، ثم «حفظ» ينسخه الى خادم جدة */
env.AI = { toMarkdown: async () => [{ data: "شهادة تسجيل في ضريبة القيمة المضافة\nالرقم الضريبي 314983900200003\nرقم السجل التجاري 7055060102\nتاريخ الشهادة 31-08-2026\nتاريخ استحقاق أول إقرار 31-10-2026\nVAT Registration Certificate" }] };
await deliver({ type: "document", document: { id: "media-1", filename: "vat.pdf", mime_type: "application/pdf" } });
const offer = sent.pop();
check("a sent paper is summarised with save / skip buttons", offer && offer.interactive && offer.interactive.action.buttons.map((button) => button.reply.id).join(",") === "doc:y,doc:n" && /314983900200003/.test(offer.interactive.body.text), show(offer));
await deliver({ type: "interactive", interactive: { type: "button_reply", button_reply: { id: "doc:y", title: "حفظ" } } });
const save = rpcCalls.filter((call) => call.name === "telegram_save_document").pop();
check("the file is copied to the Jeddah server, not linked to Meta", uploads.length === 1 && uploads[0].url.endsWith("/attachments/org-1/2026/chat/slot.pdf") && uploads[0].type === "application/pdf", show(uploads));
check("the document is saved with that storage path and the WhatsApp channel", save && save.args.p_file.storage_path === "org-1/2026/chat/slot.pdf" && save.args.p_file.channel === "whatsapp" && !save.args.p_file.external_url, show(save && save.args.p_file));

const repeat = sent.length;
await deliver({ type: "text", text: { body: "القائمة" } });
messageCounter -= 1;
await deliver({ type: "text", text: { body: "القائمة" } });
check("a message Meta sends twice is answered once", sent.length === repeat + 1, sent.length - repeat);

console.log(failed ? `\n${failed} failed` : "\nall WhatsApp checks pass");
process.exit(failed ? 1 : 0);
