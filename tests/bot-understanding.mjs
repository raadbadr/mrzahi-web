/* فهم الرسائل البديهية بلا نموذج: كل عبارة أدناه يجب أن تُفهم كما يفهمها زميل عمل.
   التشغيل: node tests/bot-understanding.mjs */
import { understand, composeAnswer, normalize } from "../src/telegram-understand.js";

let failed = 0;
function check(name, ok, detail) { if (!ok) failed++; console.log((ok ? "PASS " : "FAIL ") + name + (ok || detail === undefined ? "" : "\n      " + detail)); }
const u = (t, lang = "ar") => understand(t, lang);
const is = (t, exp) => {
  const r = u(t);
  const got = r ? { tool: r.tool, kind: r.args && r.args.kind, status: r.args && r.args.status, mode: r.args && r.args.mode, period: r.args && r.args.period, count: !!r.count, window: r.window || null, kw: !!r.keyword, reply: r.reply ? r.kind : undefined } : null;
  const ok = exp === null ? r === null : !!r && Object.keys(exp).every((k) => (exp[k] === undefined ? true : String(got[k]) === String(exp[k])));
  check(`«${t}»`, ok, JSON.stringify(got));
};
/* الأنواع الأربعة بكل صيغ السؤال */
is("قضايا", { tool: "mrzahi_items", kind: "case", status: "open" });
is("القضايا", { tool: "mrzahi_items", kind: "case" });
is("كم قضية عندنا؟", { tool: "mrzahi_items", kind: "case", count: true });
is("هل توجد مخالفات؟", { tool: "mrzahi_items", kind: "violation", status: "open" });
is("كم اجمالي المخالفات الحالية؟", { tool: "mrzahi_items", kind: "violation", status: "open", count: true });
is("كم اجمالي المخالفات بشكل عام؟", { tool: "mrzahi_items", kind: "violation", status: "all", count: true });
is("يعني ما عندنا ولا مخالفة حاليه ولا سابقه؟", { tool: "mrzahi_items", kind: "violation", status: "all" });
is("فيه مخالفات؟", { tool: "mrzahi_items", kind: "violation" });
is("عندنا غرامات", { tool: "mrzahi_items", kind: "violation" });
is("وش المهام عندي", { tool: "mrzahi_items", kind: "task" });
is("المهام المنجزة", { tool: "mrzahi_items", kind: "task", status: "done" });
is("القضايا المنجزة", { tool: "mrzahi_items", kind: "case", status: "done" });
is("مستندات", { tool: "mrzahi_items", kind: "document" });
is("وريني الأوراق", { tool: "mrzahi_items", kind: "document" });
is("show me my documents", { tool: "mrzahi_items", kind: "document" });
is("cases", { tool: "mrzahi_items", kind: "case" });
is("how many violations do we have", { tool: "mrzahi_items", kind: "violation", count: true });
is("قضايا شركة أبراج", { tool: "mrzahi_items", kind: "case" });
is("مخالفات ASKEC", { tool: "mrzahi_items", kind: "violation" });
is("القضية 4471", { tool: "mrzahi_items", kind: "case" });
is("القضية ٤٤٧١", { tool: "mrzahi_items", kind: "case" });
check("Eastern digits filter the same row as Western ones", composeAnswer(u("القضية ٤٤٧١"), [{ title: "جلسة", case_number: "4471" }, { title: "أخرى", case_number: "9" }], "ar", (r) => r.map((x) => x.title).join(","), "x") === "جلسة");
/* ورقة بعينها */
is("متى تنتهي الشهادة الضريبية", { tool: "mrzahi_items", kind: "document", kw: true });
is("رقم الشهادة الضريبية", { tool: "mrzahi_items", kind: "document", kw: true });
is("الشهادة الضريبية", { tool: "mrzahi_items", kind: "document", kw: true });
is("متى ينتهي السجل", { tool: "mrzahi_items", kind: "document", kw: true });
is("متى ينتهي", { tool: "mrzahi_items", kind: "document" });
is("تاريخ انتهاء الرخصة", { tool: "mrzahi_items", kind: "document", kw: true });
/* بطاقة الشركة */
is("رقم السجل التجاري", { tool: "mrzahi_company" });
is("كم رقم السجل", { tool: "mrzahi_company" });
is("الرقم الضريبي", { tool: "mrzahi_company" });
is("الايبان", { tool: "mrzahi_company" });
is("الشركة", { tool: "mrzahi_company" });
is("بيانات الشركة", { tool: "mrzahi_company" });
is("العنوان الوطني", { tool: "mrzahi_company" });
is("الباقة", { tool: "mrzahi_company" });
/* المواعيد */
is("مواعيد", { tool: "mrzahi_list", mode: "upcoming" });
is("وش عندي اليوم", { tool: "mrzahi_list", mode: "upcoming", window: "today" });
is("ايش عندنا بكرة", { tool: "mrzahi_list", mode: "upcoming", window: "tomorrow" });
is("مواعيد هذا الاسبوع", { tool: "mrzahi_list", mode: "upcoming", window: "week" });
is("جلسات الاسبوع", { tool: "mrzahi_list", mode: "upcoming", window: "week" });
is("المتأخرات", { tool: "mrzahi_list", mode: "overdue" });
is("ايش المتأخر عندنا", { tool: "mrzahi_list", mode: "overdue" });
is("what's overdue", { tool: "mrzahi_list", mode: "overdue" });
is("القادم", { tool: "mrzahi_list", mode: "upcoming" });
/* الفريق والمصاريف والنظرة العامة */
is("الفريق", { tool: "mrzahi_team" });
is("من في الفريق", { tool: "mrzahi_team" });
is("من المسؤول عن القضية 4471", { tool: "mrzahi_team" });
is("مصاريف", { tool: "mrzahi_expenses", period: "month" });
is("كم صرفنا هذا الشهر", { tool: "mrzahi_expenses", period: "month" });
is("مصاريف السنة", { tool: "mrzahi_expenses", period: "year" });
is("مصاريف الاسبوع", { tool: "mrzahi_expenses", period: "week" });
is("ايش اخبار المصاريف", { tool: "mrzahi_expenses" });
is("الكل", { tool: "mrzahi_overview" });
is("ملخص", { tool: "mrzahi_overview" });
is("وضعنا", { tool: "mrzahi_overview" });
is("المنجز", { tool: "mrzahi_items", kind: "all", status: "done" });
is("خلصنا", { tool: "mrzahi_items", status: "done" });
/* تحية وشكر: رد قصير بلا نموذج */
is("السلام عليكم", { reply: "greeting" });
is("كيف حالك", { reply: "about" });
is("من انت", { reply: "about" });
is("ايش تقدر تسوي", { reply: "about" });
is("what can you do", { reply: "about" });
is("هلا", { reply: "greeting" });
is("شكرا", { reply: "thanks" });
is("أحسنت", { reply: "thanks" });
is("ممتاز 👍", { reply: "thanks" });
is("تمام", { reply: "thanks" });
/* ما يُترك للمسار المؤكد أو للنموذج */
is("أنجزت القضية 4521", null);
is("خلصنا القضية 4521", null);
is("أضف مهمة مراجعة العقد غدا", null);
is("ذكرني قبل يوم بالجلسة", null);
is("أسند القضية 4471 إلى أحمد", null);
is("تأكد", null);
is("ليش", null);
is("ابغى اعرف الفرق بين القضية والدعوى", null);
/* ما سقط في تدقيق العبارات الواسع (وكلاء يولدون رسائل واقعية بلهجات مختلفة) */
is("national address", { tool: "mrzahi_company" });
is("رقم سجلنا التجاري", { tool: "mrzahi_company" });
is("commercial registration number", { tool: "mrzahi_company" });
is("رقم ضريبة القيمة المضافة", { tool: "mrzahi_company" });
is("رقمنا الموحد", { tool: "mrzahi_company" });
is("حسابنا البنكي", { tool: "mrzahi_company" });
is("رقم الحساب", { tool: "mrzahi_company" });
is("عنواننا الوطني", { tool: "mrzahi_company" });
is("باقتنا", { tool: "mrzahi_company" });
is("المؤسسة", { tool: "mrzahi_company" });
is("société", { tool: "mrzahi_company" });
is("کمپنی", { tool: "mrzahi_company" });
is("متى ينتهي سجل الشركة", { tool: "mrzahi_items", kind: "document", kw: true });
is("كم يوم باقي للسجل", { tool: "mrzahi_items", kind: "document", kw: true });
is("شهادة القيمة المضافة", { tool: "mrzahi_items", kind: "document", kw: true });
is("تأمين الموظفين", { tool: "mrzahi_items", kind: "document", kw: true });
is("اشتراك الغرفة التجارية", { tool: "mrzahi_items", kind: "document", kw: true });
is("صورة السجل التجاري", { tool: "mrzahi_items", kind: "document", kw: true });
/* النوافذ الزمنية بكل اللهجات */
is("ايش عندي بعد غد", { tool: "mrzahi_list", mode: "upcoming", window: "day_after" });
is("وش عندي بعد بكرة", { tool: "mrzahi_list", mode: "upcoming", window: "day_after" });
is("النهارده عندي ايه", { tool: "mrzahi_list", mode: "upcoming", window: "today" });
is("وش عندي باكر", { tool: "mrzahi_list", mode: "upcoming", window: "tomorrow" });
is("what do i have tommorow", { tool: "mrzahi_list", mode: "upcoming", window: "tomorrow" });
is("whats on tmrw", { tool: "mrzahi_list", mode: "upcoming", window: "tomorrow" });
is("شي لليوم؟", { tool: "mrzahi_list", mode: "upcoming", window: "today" });
is("عندي شي الليلة", { tool: "mrzahi_list", mode: "upcoming", window: "today" });
is("مواعيد هالاسبوع", { tool: "mrzahi_list", mode: "upcoming", window: "week" });
is("هاليوم وش عندي", { tool: "mrzahi_list", mode: "upcoming", window: "today" });
is("وش عندي هذا الشهر", { tool: "mrzahi_list", mode: "upcoming", window: "month" });
is("اليومين الجاية", { tool: "mrzahi_list", mode: "upcoming" });
is("وش عندي اليوم وبكرة", { tool: "mrzahi_list", mode: "upcoming", window: "today_tomorrow" });
is("مواعيد الاسبوع الماضي", { tool: "mrzahi_list", mode: "overdue" });
is("متى اقرب جلسة", { tool: "mrzahi_list", mode: "upcoming" });
is("متى الجلسة القادمة", { tool: "mrzahi_list", mode: "upcoming" });
is("when is the next hearing", { tool: "mrzahi_list", mode: "upcoming" });
is("qu'est-ce que j'ai aujourd'hui", { tool: "mrzahi_list", mode: "upcoming", window: "today" });
is("rendez-vous demain", { tool: "mrzahi_list", mode: "upcoming", window: "tomorrow" });
is("échéances cette semaine", { tool: "mrzahi_list", mode: "upcoming", window: "week" });
is("آج کیا ہے", { tool: "mrzahi_list", mode: "upcoming", window: "today" });
is("اس ہفتے کی تاریخیں", { tool: "mrzahi_list", mode: "upcoming", window: "week" });
is("وش ينتهي هذا الاسبوع", { tool: "mrzahi_items", kind: "document", window: "week" });
is("المستندات اللي تنتهي هذا الاسبوع", { tool: "mrzahi_items", kind: "document", window: "week" });
is("4471", { tool: "mrzahi_search" });
is("رقم 4471", { tool: "mrzahi_search" });
is("٤٤٧١", { tool: "mrzahi_search" });
is("المهام المنجزة هذا الشهر", { tool: "mrzahi_items", kind: "task", status: "done" });
/* نوافذ التركيب: بعد غد، اليوم وغدا، الشهر */
{
  const day = (k) => new Date(Date.now() + k * 86400000).toISOString();
  const rows = [{ title: "اليوم", due_at: day(0) }, { title: "غدا", due_at: day(1) }, { title: "بعد غد", due_at: day(2) }];
  const txt = (r) => r.map((x) => x.title).join(",");
  check("«بعد غد» keeps only the day after tomorrow", composeAnswer(u("ايش عندي بعد غد"), rows, "ar", txt, "x", "Asia/Riyadh") === "بعد غد");
  check("«اليوم وبكرة» keeps both days", composeAnswer(u("وش عندي اليوم وبكرة"), rows, "ar", txt, "x", "Asia/Riyadh") === "اليوم,غدا");
  check("an empty window lists the nearest by date, soonest first", /الأقرب:\naليوم|الأقرب:\nاليوم/.test(composeAnswer(u("ايش عندي بعد غد"), [{ title: "اليوم", due_at: day(0) }], "ar", txt, "x", "Asia/Riyadh")));
}

/* بيانات المنصة كلها: لمدير المنصة وحده، ولا تخلط بالفريق */
is("كم المسجلين في الموقع", { tool: "mrzahi_platform" });
is("كم عدد المستخدمين", { tool: "mrzahi_platform" });
is("المشتركين في المنصة", { tool: "mrzahi_platform" });
is("how many users on the site", { tool: "mrzahi_platform" });
is("في الموقع بالكامل", { tool: "mrzahi_platform" });
is("الفريق", { tool: "mrzahi_team" });

/* التطبيع */
check("normalize: hamza, taa marbuta, diacritics, punctuation", normalize("الشَّهادةُ الضريبيّة؟ أإآ ى") === "الشهاده الضريبيه ااا ي", normalize("الشَّهادةُ الضريبيّة؟ أإآ ى"));
/* تركيب الجواب */
const rowsText = (rows) => rows.map((r) => r.title).join("\n");
const docs = [{ title: "السجل التجاري — PARKINZI Company", document_kind: "commercial_register", doc_number: "7055060102", due_at: "2027-09-01T00:00:00Z" }, { title: "الشهادة الضريبية — PARKINZI Company", document_kind: "vat_certificate", doc_number: "314983900200003", due_at: "2026-10-31T00:00:00Z" }];
check("«متى تنتهي الشهادة الضريبية» narrows to the VAT paper", composeAnswer(u("متى تنتهي الشهادة الضريبية"), docs, "ar", rowsText, "x") === "الشهادة الضريبية — PARKINZI Company", composeAnswer(u("متى تنتهي الشهادة الضريبية"), docs, "ar", rowsText, "x"));
check("«كم مستند عندنا» counts and stops there", String(composeAnswer(u("كم مستند عندنا"), docs, "ar", rowsText, "x")) === "المستندات: 2", composeAnswer(u("كم مستند عندنا"), docs, "ar", rowsText, "x"));
check("a keyword that matches nothing says so and still shows the list", String(composeAnswer(u("متى تنتهي الرخصة"), docs, "ar", rowsText, "x")).startsWith("لا شيء بهذه الكلمة ضمن المستندات (2)."), composeAnswer(u("متى تنتهي الرخصة"), docs, "ar", rowsText, "x"));
const soon = new Date(Date.now() + 3 * 86400000).toISOString(), far = new Date(Date.now() + 40 * 86400000).toISOString();
check("«وش عندي اليوم» with nothing today shows the nearest instead", /^لا مواعيد اليوم\.\nالأقرب:\n/.test(String(composeAnswer(u("وش عندي اليوم"), [{ title: "جلسة", due_at: soon }, { title: "بعيد", due_at: far }], "ar", rowsText, "x", "Asia/Riyadh"))));
check("«مواعيد هذا الاسبوع» keeps only this week's", composeAnswer(u("مواعيد هذا الاسبوع"), [{ title: "جلسة", due_at: soon }, { title: "بعيد", due_at: far }], "ar", rowsText, "x", "Asia/Riyadh") === "جلسة");
check("empty rows fall back to the tool's wide-look text", composeAnswer(u("مخالفات"), [], "ar", rowsText, "لا مخالفات مسجلة إطلاقا") === "لا مخالفات مسجلة إطلاقا");
console.log(failed ? `\n${failed} check(s) failed` : "\nall understanding checks pass");
process.exit(failed ? 1 : 0);
