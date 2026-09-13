/* season.js — تفعيل موسم اليوم الوطني قبل اول رسم.

   كان هذا كله في ‎brand-logo.js‎ المؤجل في اخر ‎<body>‎، فترسم الصفحة بالتصميم
   القديم اولا ثم تقفز الى الموسم حين ياتي دور السكربت — قيس على جوال مخنوق:
   نحو 400 مللي ثانية في صفحة الباقات، وفوق ثانيتين في الرئيسية لان الحزمة
   الكبيرة تسبقه في الترتيب. لذلك خرج الى ملف صغير يحمّل في ‎<head>‎ بلا
   ‎defer‎ ولا ‎async‎، فيضبط السمات قبل ان يرسم المتصفح اي بكسل.
   ولا يجوز ان يكون داخليا: سياسة الامان تحجب ‎script-src‎ الداخلي.

   يبقى في ‎brand-logo.js‎ ما لا يخص الرسم الاول: استبدال كلمة MrZahi بالشعار. */

/* موسم اليوم الوطني: طبقة الوان موقتة تشتغل في سبتمبر وحده وترجع الهوية بعده
   (امر المهندس رعد 2026-09-11). ‎?season=off‎ يطفئها و‎?season=nd96‎ يجربها في اي وقت.
   قواعدها كتلة واحدة في header.css، ولا تمس شعارا ولا ايقونة. */
(function () {
  try {
    var on = new Date().getMonth() === 8;
    var q = String(window.location.search || "");
    if (q.indexOf("season=off") !== -1) on = false;
    else if (q.indexOf("season=nd96") !== -1) on = true;
    if (on) {
      var doc = document.documentElement;
      doc.setAttribute("data-season", "nd96");
      /* قيم الهوية الست: لكل يوم قيمة كاملة لا عبارة وحدها — عبارتها وبلاطتها
         ولونها، كما رتبها دليل الهوية. ‎?nd=tree‎ وما شابهه يثبت قيمة بعينها
         للمعاينة. المفتاح يذهب الى ‎data-nd-value‎ فتتبعه قواعد header.css. */
      var VALUES = [
        { key: "authenticity",  slogan: "عزنا باصالتنا" },
        { key: "generosity",    slogan: "عزنا بكرمنا" },
        { key: "courage",       slogan: "عزنا بشجاعتنا" },
        { key: "determination", slogan: "عزنا بهمتنا" },
        { key: "giving",        slogan: "عزنا بجودنا" },
        { key: "vision",        slogan: "عزنا برؤيتنا" }
      ];
      var v = VALUES[new Date().getDate() % VALUES.length];
      var forced = q.match(/[?&]nd=([a-z]+)/);
      if (forced) {
        for (var i = 0; i < VALUES.length; i++) {
          if (VALUES[i].key === forced[1]) { v = VALUES[i]; break; }
        }
      }
      doc.setAttribute("data-nd-slogan", v.slogan);
      doc.setAttribute("data-nd-value", v.key);
      /* الراس ينمو بقدر الشريط بعد ضبط السمة، و‎syncSiteHeaderHeight‎ تكون قد قاسته
         قبلها؛ وهي مربوطة بـ‎resize‎ فنطلقه ليعاد القياس وينزل ما يعتمد عليه. */
      var again = function () { try { window.dispatchEvent(new Event("resize")); } catch (e) {} };
      again();
      window.addEventListener("load", again);
    }
  } catch (e) { /* الثيم الاصلي يبقى */ }
})();

/* شعار الموسم: نسخة من الشعار نفسه بلون الهوية بدل الازرق السماوي — الليموني
   ‎#5aba1c‎ على الداكن والاخضر ‎#008949‎ على الفاتح، والحرفان ‎MR‎ كما هما.
   مصدر الشعار مثبت نصا في عشرة ملفات (سكربتات كل صفحة تبدله مع الثيم)، فبدل
   ملاحقتها كلها نمسح الصور مرة عند البدء ونراقب سمة ‎src‎ فنبدل ما يوضع لاحقا.
   تزول الطبقة بزوال ‎data-season‎ فيرجع الازرق بلا لمس اي ملف اخر. */
(function () {
  var ND = document.documentElement.getAttribute('data-season') === 'nd96';
  var RE = /mrzahi-logo-full-(dark|light)\.png/;
  function seasonal(src) {
    if (!ND || !src || src.indexOf('-nd96') !== -1) return src;
    return src.replace(RE, 'mrzahi-logo-full-$1-nd96.png');
  }
  function sweep(root) {
    if (!ND || !root || !root.querySelectorAll) return;
    var imgs = root.querySelectorAll('img[src*="mrzahi-logo-full-"]');
    for (var i = 0; i < imgs.length; i++) {
      var cur = imgs[i].getAttribute('src'); var next = seasonal(cur);
      if (next !== cur) imgs[i].setAttribute('src', next);
    }
  }
  if (ND && typeof MutationObserver !== 'undefined') {
    new MutationObserver(function (recs) {
      for (var i = 0; i < recs.length; i++) {
        var r = recs[i];
        if (r.type === 'attributes' && r.target.tagName === 'IMG') {
          var cur = r.target.getAttribute('src'); var next = seasonal(cur);
          if (next !== cur) r.target.setAttribute('src', next);
        } else if (r.type === 'childList') {
          for (var j = 0; j < r.addedNodes.length; j++) {
            var n = r.addedNodes[j];
            if (n.nodeType !== 1) continue;
            if (n.tagName === 'IMG') { var c = n.getAttribute('src'); var x = seasonal(c); if (x !== c) n.setAttribute('src', x); }
            else sweep(n);
          }
        }
      }
    }).observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ['src'] });
  }
  if (ND) {
    sweep(document);
    document.addEventListener('DOMContentLoaded', function () { sweep(document); });
  }

  /* ‎brand-logo.js‎ يبني صورا لاحقا فيحتاج الدالة نفسها */
  window.__ndSeasonal = seasonal;
})();
