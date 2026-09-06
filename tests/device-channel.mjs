/* قناة الجهاز (شاشة زاهي): التشكيل العربي البصري وصيغة المواعيد التي يفهمها الفيرموير.
   التشغيل: node tests/device-channel.mjs */
import { shapeArabic, toVisual, forDevice, fitDevice } from "../src/arabic-shape.js";
import { buildDevicePayload, localEpoch } from "../src/calendar.js";

let failed = 0;
function check(name, ok, detail) { if (!ok) failed++; console.log((ok ? "PASS " : "FAIL ") + name + (ok || detail === undefined ? "" : "\n      " + detail)); }
const codes = (s) => [...s].map((c) => c.codePointAt(0).toString(16).toUpperCase().padStart(4, "0")).join(" ");
const bytes = (s) => new TextEncoder().encode(s).length;

/* --- الوصل: الشكل يتبع الجار، والجدول من يونيكود نفسه --- */
check("a letter between two joiners takes the medial form", codes(shapeArabic("ببب")) === "FE91 FE92 FE90", codes(shapeArabic("ببب")));
check("alef never joins forward, so what follows starts fresh", codes(shapeArabic("اب")) === "FE8D FE8F", codes(shapeArabic("اب")));
check("lam and alef become one glyph", codes(shapeArabic("لا")) === "FEFB", codes(shapeArabic("لا")));
check("lam-alef after a joiner takes its final form", codes(shapeArabic("سلا")) === "FEB3 FEFC", codes(shapeArabic("سلا")));
check("«السلام» shapes exactly as the eye reads it", codes(shapeArabic("السلام")) === "FE8D FEDF FEB4 FEFC FEE1", codes(shapeArabic("السلام")));
check("diacritics and tatweel are dropped before shaping", shapeArabic("مُحَمَّـ__د".replace(/_/g, "")) === shapeArabic("محمد"), codes(shapeArabic("مُحَمَّد")));
check("a word with no Arabic passes through untouched", shapeArabic("PARKINZI 2026") === "PARKINZI 2026");

/* --- الترتيب البصري: الشاشة ترسم من اليسار، فالحروف تُقلب والأرقام لا --- */
check("the line is mirrored so it reads right to left on screen", toVisual("ابج") === "جبا");
check("digits keep their own order inside the mirrored line", toVisual("جلسة 4471") === "4471 ةسلج", toVisual("جلسة 4471"));
check("a Latin word keeps its order and moves to the left", toVisual("شركة PARKINZI") === "PARKINZI ةكرش", toVisual("شركة PARKINZI"));
check("brackets mirror with the line", toVisual("(جلسة)") === "(ةسلج)", toVisual("(جلسة)"));
check("a date reads correctly on screen", toVisual("موعد 10-09-2026") === "10-09-2026 دعوم", toVisual("موعد 10-09-2026"));

/* --- شكل + ترتيب معا: ما يُرسل فعلا --- */
check("«جلسة 4471» reaches the device shaped and mirrored", codes(forDevice("جلسة 4471")) === "0034 0034 0037 0031 0020 FE94 FEB4 FEE0 FE9F", codes(forDevice("جلسة 4471")));

/* --- حد 83 بايتا: كلمات كاملة لا حروف مبتورة --- */
{
  const long = "الشهادة الضريبية لشركة باركنزي المحدودة للتقنية والاستثمار في الرياض";
  const cut = fitDevice(long, 83);
  check("a long title is cut to fit the device byte limit", bytes(cut) <= 83, String(bytes(cut)));
  check("the cut lands on a word, never inside one", cut === forDevice("الشهادة الضريبية لشركة"), cut);
  check("a title that fits is not touched", fitDevice("جلسة", 83) === forDevice("جلسة"));
  const oneWord = "ا".repeat(60);
  check("a single word longer than the limit is cut by letters", bytes(fitDevice(oneWord, 83)) <= 83);
  check("the separators the firmware parses are stripped from titles", !/[|;]/.test(fitDevice("جلسة | مهمة ; أخرى", 83)), fitDevice("جلسة | مهمة ; أخرى", 83));
}

/* --- الساعة: الجهاز بلا منطقة زمنية، فيأخذ لحظة الحائط جاهزة --- */
{
  const iso = "2026-09-10T06:00:00.000Z"; /* 09:00 بتوقيت الرياض */
  const e = localEpoch(iso, "Asia/Riyadh");
  check("local epoch is the wall clock in Riyadh, not UTC", e === Date.UTC(2026, 8, 10, 9, 0, 0) / 1000, String(e));
  check("an unreadable date returns nothing rather than a wrong time", localEpoch("not a date", "Asia/Riyadh") === null);
}

/* --- الحمولة كاملة كما يقرؤها الفيرموير --- */
{
  const now = Date.parse("2026-09-06T09:00:00.000Z");
  const items = [
    { title: "جلسة الاستئناف 4471", due_at: "2026-09-06T05:00:00.000Z" },   /* مضى عليه أكثر من نصف ساعة */
    { title: "تجديد السجل التجاري", due_at: "2026-09-08T06:00:00.000Z" },
    { title: "جلسة", due_at: "2026-09-07T07:30:00.000Z" },
    { title: "بلا موعد", due_at: null },
    { title: "الشهادة الضريبية", due_at: "2026-09-09T06:00:00.000Z" },
    { title: "مهمة خامسة", due_at: "2026-09-10T06:00:00.000Z" },
    { title: "مهمة سادسة", due_at: "2026-09-11T06:00:00.000Z" },
  ];
  const payload = buildDevicePayload(items, { now });
  const rows = payload.split(";");
  check("at most four appointments reach a screen that holds four", rows.length === 4, String(rows.length));
  check("every row is epoch|title", rows.every((r) => /^\d+\|[^|]+$/.test(r)), payload);
  check("what has passed by more than half an hour is dropped", !payload.includes(forDevice("جلسة الاستئناف 4471")), payload);
  check("an item with no due date is dropped", !payload.includes(forDevice("بلا موعد")));
  check("the soonest comes first", Number(rows[0].split("|")[0]) < Number(rows[1].split("|")[0]));
  check("titles arrive shaped and mirrored", rows[0].split("|")[1] === forDevice("جلسة"), rows[0]);
  check("no row exceeds the firmware's byte limit", rows.every((r) => bytes(r.split("|")[1]) <= 83));
  check("the payload never carries a newline the parser would choke on", !/[\r\n]/.test(payload));
  const one = buildDevicePayload(items, { now, max: 1 });
  check("the count can be narrowed for a smaller screen", one.split(";").length === 1);
  check("nothing due at all gives an empty body, not a lie", buildDevicePayload([], { now }) === "");
}

console.log(failed ? `\n${failed} check(s) failed` : "\nall device checks pass");
process.exit(failed ? 1 : 0);
