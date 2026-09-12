/* صفحة عبور لباركود شاشة زاهي: تتحقق ان العنوان محلي ثم تنتقل الى بطاقة التقويم في
   الاعدادات حيث زر «اربط شاشتي». ملف خارجي لان سياسة الامان تحجب السكربت الداخلي. */
(function () {
  var to = "";
  try { to = String(new URLSearchParams(window.location.search).get("to") || "").trim().toLowerCase(); } catch (e) { to = ""; }
  /* عناوين الشبكة المحلية فقط: 10.x و172.16-31.x و192.168.x او اسم ينتهي بـ .local؛
     اي شيء غير ذلك يرفض كي لا يصنع احد رابطا يسرب الرمز الى خادم غريب */
  var ok = to.length <= 64 && /^(?:10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}|[a-z0-9-]+\.local)$/.test(to);
  var title = document.getElementById("title"), msg = document.getElementById("msg"), msgEn = document.getElementById("msgEn"), btn = document.getElementById("btn");
  if (ok) {
    var target = "/app/settings.html?link=" + encodeURIComponent(to) + "#calendarCard";
    /* الزر احتياط ان حجب الانتقال التلقائي لاي سبب */
    if (btn) { btn.href = target; btn.hidden = false; }
    window.location.replace(target);
    return;
  }
  if (title) title.textContent = "رابط الربط غير صالح";
  if (msg) msg.textContent = "امسح الباركود الظاهر على شاشة زاهي مرة اخرى وجوالك على شبكة الجهاز نفسها.";
  if (msgEn) msgEn.textContent = "Invalid link. Scan the code on the Zahi screen again while your phone is on the device's network.";
  if (btn) btn.hidden = false;
})();
