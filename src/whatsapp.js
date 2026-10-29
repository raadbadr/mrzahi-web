/* WhatsApp Cloud API — القناة الثانية للبوت بالعقل نفسه (امر المهندس رعد 2026-10-29).
   محادثة WhatsApp معرفها في البوت wa:<الرقم الدولي>، فتمر في مسارات تيليغرام نفسها (السجل والمسودات
   والوكيل) بلا اختلاط. الازرار تكتب في الشيفرة بصيغة تيليغرام (reply_markup) وتحول هنا الى رسائل WhatsApp
   التفاعلية: ثلاثة ازرار او اقل ← ازرار رد، واكثر ← قائمة حتى 10 خيارات، ورابط واحد ← زر رابط.
   حدود Meta: نص الرسالة 4096 حرفا، ونص الرسالة التفاعلية 1024، وعنوان الزر 20، وعنوان صف القائمة 24. */

const GRAPH = "https://graph.facebook.com/v21.0";
export const WHATSAPP_FILE_MAX = 15 * 1024 * 1024;
const TEXT_MAX = 4096;
const BODY_MAX = 1024;
const BUTTON_TITLE_MAX = 20;
const BUTTONS_MAX = 3;
const ROW_TITLE_MAX = 24;
const ROW_DESCRIPTION_MAX = 72;
const ROWS_MAX = 10;
const PICK_LABEL = { ar: "اختر", en: "Choose", fr: "Choisir", ur: "منتخب کریں" };
const MENU_LABEL = { ar: "القائمة", en: "Menu", fr: "Menu", ur: "مینو" };

export function whatsappConfigured(env) { return !!(env.WHATSAPP_TOKEN && env.WHATSAPP_PHONE_ID); }
export function isWhatsappChat(chatId) { return String(chatId || "").startsWith("wa:"); }
export function whatsappChatId(phone) { return "wa:" + String(phone || "").replace(/\D/g, ""); }
export function whatsappPhone(chatId) { return String(chatId || "").replace(/^wa:/, "").replace(/\D/g, ""); }

/* لغة النص لعنوان زر القائمة: حروف الاردية الخاصة، ثم العربية، ثم الفرنسية بحروفها، والا الانجليزية */
function textLang(text) {
  const value = String(text || "");
  if (/[ٹڈڑںےہکگ]/.test(value)) return "ur";
  if (/[؀-ۿ]/.test(value)) return "ar";
  if (/[àâçéèêëîïôûùüÿœ]/i.test(value)) return "fr";
  return "en";
}

/* نص طويل يقسم عند فواصل الاسطر، فلا تقطع كلمة ولا يضيع شيء */
function splitText(text) {
  const chunks = [];
  let rest = String(text || "");
  while (rest.length > TEXT_MAX) {
    let cut = rest.lastIndexOf("\n", TEXT_MAX);
    if (cut < TEXT_MAX / 2) cut = rest.lastIndexOf(" ", TEXT_MAX);
    if (cut < TEXT_MAX / 2) cut = TEXT_MAX;
    chunks.push(rest.slice(0, cut));
    rest = rest.slice(cut).replace(/^\s+/, "");
  }
  if (rest) chunks.push(rest);
  return chunks;
}

function textMessage(body) {
  return { type: "text", text: { body, preview_url: false } };
}

function choiceMessage(body, choices, lang) {
  const fitsButtons = choices.length <= BUTTONS_MAX && choices.every((choice) => choice.title.length <= BUTTON_TITLE_MAX);
  if (fitsButtons) {
    return { type: "interactive", interactive: { type: "button", body: { text: body },
      action: { buttons: choices.map((choice) => ({ type: "reply", reply: { id: choice.id, title: choice.title } })) } } };
  }
  /* العنوان الطويل يكتب كاملا في وصف الصف، والعنوان رقمه، فلا يقص اسم شركة ولا خيار */
  const rows = choices.slice(0, ROWS_MAX).map((choice, index) => choice.title.length <= ROW_TITLE_MAX
    ? { id: choice.id, title: choice.title }
    : { id: choice.id, title: String(index + 1), description: choice.title.slice(0, ROW_DESCRIPTION_MAX) });
  return { type: "interactive", interactive: { type: "list", body: { text: body },
    action: { button: PICK_LABEL[lang] || PICK_LABEL.ar, sections: [{ rows }] } } };
}

/* نص وازرار بصيغة تيليغرام ← رسائل WhatsApp بالترتيب. menuId يحول نص زر القائمة الدائمة الى فعله */
export function whatsappMessages(text, extra, menuId) {
  const markup = (extra && extra.reply_markup) || {};
  const inline = Array.isArray(markup.inline_keyboard) ? markup.inline_keyboard.flat().filter(Boolean) : [];
  const choices = inline.filter((button) => button.callback_data).map((button) => ({ id: String(button.callback_data), title: String(button.text || "").trim() || "-" }));
  const links = inline.filter((button) => button.url && /^https:\/\//.test(button.url));
  const keyboard = Array.isArray(markup.keyboard) ? markup.keyboard.flat().filter((button) => button && button.text && !button.request_contact) : [];
  const menu = typeof menuId === "function"
    ? keyboard.map((button) => ({ id: menuId(button.text), title: String(button.text) })).filter((choice) => choice.id).map((choice) => ({ id: "menu:" + choice.id, title: choice.title }))
    : [];
  let body = String(text || "").trim() || "-";
  const lang = textLang(body);
  const messages = [];
  let interactive = null;

  if (choices.length) {
    /* الروابط مع الازرار تكتب في النص: WhatsApp لا يجمع زر رد وزر رابط في رسالة */
    if (links.length) body += "\n\n" + links.map((link) => link.text + ": " + link.url).join("\n");
    interactive = (head) => choiceMessage(head, choices, lang);
  } else if (links.length === 1 && String(links[0].text || "").length <= BUTTON_TITLE_MAX) {
    const link = links[0];
    interactive = (head) => ({ type: "interactive", interactive: { type: "cta_url", body: { text: head },
      action: { name: "cta_url", parameters: { display_text: String(link.text), url: link.url } } } });
  } else if (links.length) {
    body += "\n\n" + links.map((link) => link.text + ": " + link.url).join("\n");
  } else if (menu.length && body.length <= BODY_MAX) {
    interactive = (head) => ({ type: "interactive", interactive: { type: "list", body: { text: head },
      action: { button: MENU_LABEL[lang] || MENU_LABEL.ar, sections: [{ rows: menu.slice(0, ROWS_MAX).map((choice) => ({ id: choice.id, title: choice.title.slice(0, ROW_TITLE_MAX) })) }] } } });
  }

  if (!interactive) return splitText(body).map(textMessage);
  if (body.length <= BODY_MAX) return [interactive(body)];
  /* نص اطول من حد الرسالة التفاعلية: يرسل كاملا، ثم الازرار تحته */
  for (const chunk of splitText(body)) messages.push(textMessage(chunk));
  messages.push(interactive("👆"));
  return messages;
}

async function postMessage(env, to, message) {
  const res = await fetch(`${GRAPH}/${env.WHATSAPP_PHONE_ID}/messages`, {
    method: "POST",
    headers: { Authorization: `Bearer ${env.WHATSAPP_TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify({ messaging_product: "whatsapp", recipient_type: "individual", to, ...message }),
  });
  if (!res.ok) throw new Error(`whatsapp ${res.status}: ${(await res.text()).slice(0, 200)}`);
  return true;
}

export async function sendWhatsappChat(env, chatId, text, extra, menuId) {
  if (!whatsappConfigured(env)) throw new Error("whatsapp not configured");
  const to = whatsappPhone(chatId);
  if (!to) throw new Error("whatsapp: no recipient");
  for (const message of whatsappMessages(text, extra, menuId)) await postMessage(env, to, message);
  return true;
}

/* «يكتب الآن…» ريثما يحضر الرد، مع علامة القراءة على رسالة المستخدم */
export async function whatsappTyping(env, messageId) {
  if (!whatsappConfigured(env) || !messageId) return;
  try {
    await fetch(`${GRAPH}/${env.WHATSAPP_PHONE_ID}/messages`, {
      method: "POST",
      headers: { Authorization: `Bearer ${env.WHATSAPP_TOKEN}`, "Content-Type": "application/json" },
      body: JSON.stringify({ messaging_product: "whatsapp", status: "read", message_id: messageId, typing_indicator: { type: "text" } }),
    });
  } catch {}
}

/* ملف ارسله المستخدم: معرفه يعطي رابطا يعيش خمس دقائق، والتنزيل يحتاج المفتاح نفسه */
export async function fetchWhatsappMedia(env, mediaId) {
  if (!whatsappConfigured(env)) throw new Error("whatsapp not configured");
  const auth = { Authorization: `Bearer ${env.WHATSAPP_TOKEN}` };
  const info = await fetch(`${GRAPH}/${encodeURIComponent(mediaId)}`, { headers: auth }).then((res) => res.json());
  if (!info || !info.url) throw new Error("whatsapp media lookup failed");
  if (Number(info.file_size || 0) > WHATSAPP_FILE_MAX) throw new Error("file too big");
  const res = await fetch(info.url, { headers: auth });
  if (!res.ok) throw new Error(`whatsapp media download ${res.status}`);
  const bytes = await res.arrayBuffer();
  if (bytes.byteLength > WHATSAPP_FILE_MAX) throw new Error("file too big");
  return { bytes, mime: info.mime_type || "", size: bytes.byteLength };
}
