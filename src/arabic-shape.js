/* تشكيل العربية لشاشة زاهي 480x480.
   الدليل من الفيرموير نفسه في ~/Documents/Arduino/ZahiRobot/Zahi-Touch/Zahi-Touch.ino:
   دالة textAA في السطر 10048 تمشي على النص محرفا محرفا وترسم كل محرف كما هو
   وتزيد penX الى اليمين، بلا وصل وبلا عكس. وجدول الخط فيه 288 رسما في نطاق
   اشكال العرض FE70-FEFF مقابل 24 رسما في النطاق الاساسي 06xx. وتعليق السطر 10072
   في الفيرموير ينص: «نصوص زاهي العربية تصل مشكلة بترتيب العرض — ترسم محرفا محرفا».
   فالجهاز يحتاج النص مشكلا ومقلوبا جاهزا، وهذا ما تفعله هذه الوحدة.
   يحول النص المنطقي إلى أشكال العرض التقديمية (Arabic Presentation Forms-B) ثم يرتبه بصريا،
   فيقرأ صحيحا على شاشة ترسم الحروف من اليسار إلى اليمين كما هي.
   الجدولان مشتقان من بيانات يونيكود نفسها لا من تقدير: لكل حرف [منفصل، نهائي، ابتدائي، وسطي]. */

const FORMS = { 1569:[65152,0,0,0], 1570:[65153,65154,0,0], 1571:[65155,65156,0,0], 1572:[65157,65158,0,0], 1573:[65159,65160,0,0], 1574:[65161,65162,65163,65164], 1575:[65165,65166,0,0], 1576:[65167,65168,65169,65170], 1577:[65171,65172,0,0], 1578:[65173,65174,65175,65176], 1579:[65177,65178,65179,65180], 1580:[65181,65182,65183,65184], 1581:[65185,65186,65187,65188], 1582:[65189,65190,65191,65192], 1583:[65193,65194,0,0], 1584:[65195,65196,0,0], 1585:[65197,65198,0,0], 1586:[65199,65200,0,0], 1587:[65201,65202,65203,65204], 1588:[65205,65206,65207,65208], 1589:[65209,65210,65211,65212], 1590:[65213,65214,65215,65216], 1591:[65217,65218,65219,65220], 1592:[65221,65222,65223,65224], 1593:[65225,65226,65227,65228], 1594:[65229,65230,65231,65232], 1601:[65233,65234,65235,65236], 1602:[65237,65238,65239,65240], 1603:[65241,65242,65243,65244], 1604:[65245,65246,65247,65248], 1605:[65249,65250,65251,65252], 1606:[65253,65254,65255,65256], 1607:[65257,65258,65259,65260], 1608:[65261,65262,0,0], 1609:[65263,65264,0,0], 1610:[65265,65266,65267,65268] };
/* لام + ألف: حرف واحد على الشاشة [منفصل، نهائي] */
const LAM_ALEF = { 1570:[65269,65270], 1571:[65271,65272], 1573:[65273,65274], 1575:[65275,65276] };
const LAM = 1604;
const TATWEEL = 1600;

/* الحركات والتشكيل تحذف قبل كل شيء: قاعدة المشروع، وخطوط الجهاز لا ترسمها أصلا */
function stripMarks(text) {
  return String(text || "").replace(/[\u064B-\u065F\u0670\u06D6-\u06ED]/g, "").replace(/\u0640/g, "");
}
const isArabic = (cp) => (cp >= 0x0600 && cp <= 0x06FF) || (cp >= 0xFB50 && cp <= 0xFEFF);
/* حرف يصل بما بعده (له شكل ابتدائي)، وحرف يقبل الوصل بما قبله (له شكل نهائي) */
const joinsForward = (cp) => !!(FORMS[cp] && FORMS[cp][2]);
const joinsBackward = (cp) => !!(FORMS[cp] && FORMS[cp][1]);

/* المنطقي إلى أشكال العرض، بلا عكس */
export function shapeArabic(text) {
  const src = [...stripMarks(text)].map((c) => c.codePointAt(0));
  const out = [];
  let prevJoins = false; /* هل الحرف السابق يصل بما بعده */
  for (let i = 0; i < src.length; i++) {
    const cp = src[i];
    /* لام ألف: حرف واحد */
    if (cp === LAM && LAM_ALEF[src[i + 1]]) {
      const pair = LAM_ALEF[src[i + 1]];
      out.push(prevJoins && pair[1] ? pair[1] : pair[0]);
      prevJoins = false; /* الألف لا تصل بما بعدها */
      i += 1;
      continue;
    }
    const f = FORMS[cp];
    if (!f) { out.push(cp); if (!isArabic(cp) && cp !== TATWEEL) prevJoins = false; continue; }
    const nextCp = src[i + 1];
    const nextJoinable = nextCp !== undefined && joinsBackward(nextCp);
    let form;
    if (prevJoins && joinsForward(cp) && nextJoinable) form = f[3] || f[1] || f[0];
    else if (joinsForward(cp) && nextJoinable) form = f[2] || f[0];
    else if (prevJoins) form = f[1] || f[0];
    else form = f[0];
    out.push(form);
    prevJoins = joinsForward(cp);
  }
  return String.fromCodePoint(...out);
}

const MIRROR = { "(": ")", ")": "(", "[": "]", "]": "[", "{": "}", "}": "{", "<": ">", ">": "<", "«": "»", "»": "«" };
/* الترتيب البصري: يعكس السطر، وتبقى الأرقام والكلمات اللاتينية بترتيبها كي تقرأ صحيحة */
export function toVisual(text) {
  const runs = String(text || "").match(/[A-Za-z0-9@._:\/+-]+|[\s\S]/g) || [];
  const out = [];
  for (let i = runs.length - 1; i >= 0; i--) {
    const r = runs[i];
    out.push(r.length > 1 ? r : (MIRROR[r] || r));
  }
  return out.join("");
}

/* ما يرسل إلى الجهاز: مشكل ومرتب بصريا */
export function forDevice(text) {
  return toVisual(shapeArabic(text));
}

/* قص إلى حد بايتات الجهاز مع إبقاء الكلمات كاملة، ثم التشكيل (القص قبل التشكيل كي يبقى الوصل صحيحا) */
export function fitDevice(text, maxBytes) {
  const limit = Math.max(8, Number(maxBytes) || 83);
  const enc = new TextEncoder();
  let words = stripMarks(text).replace(/[|;\r\n]+/g, " ").replace(/\s+/g, " ").trim().split(" ");
  while (words.length) {
    const candidate = forDevice(words.join(" "));
    if (enc.encode(candidate).length <= limit) return candidate;
    words.pop();
  }
  /* كلمة واحدة أطول من الحد: تقص حرفا حرفا */
  let one = stripMarks(text).trim();
  while (one.length && enc.encode(forDevice(one)).length > limit) one = one.slice(0, -1);
  return forDevice(one);
}
