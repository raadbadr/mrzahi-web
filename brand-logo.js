/**
 * brand-logo.js
 * Replaces every visible occurrence of the literal text "MrZahi"
 * with the wordmark image, following the active theme.
 */
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

  var LOGO_DARK = seasonal('/mrzahi-logo-full-dark.png') + '?v=2';
  var LOGO_LIGHT = seasonal('/mrzahi-logo-full-light.png') + '?v=2';
  var SKIP_SELECTOR = 'script, style, noscript, code, pre, title, .brand-logo-mark, .brand-logo-inline, [data-brand-logo-footer]';
  var TARGET = 'MrZahi';

  function logoSrc() {
    return document.documentElement.getAttribute('data-theme') === 'light' ? LOGO_LIGHT : LOGO_DARK;
  }

  function makeLogo() {
    var img = document.createElement('img');
    img.src = logoSrc();
    img.alt = TARGET;
    img.className = 'brand-logo-mark';
    img.loading = 'lazy';
    img.decoding = 'async';
    return img;
  }

  function syncTheme() {
    var src = logoSrc();
    var marks = document.querySelectorAll('img.brand-logo-mark');
    for (var i = 0; i < marks.length; i++) marks[i].src = src;
  }

  function replaceInBody() {
    if (!document.body) return 0;
    var walker = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_TEXT,
      {
        acceptNode: function (node) {
          var p = node.parentElement;
          if (!p) return NodeFilter.FILTER_REJECT;
          if (p.closest(SKIP_SELECTOR)) return NodeFilter.FILTER_REJECT;
          if (node.nodeValue.indexOf(TARGET) === -1) return NodeFilter.FILTER_REJECT;
          return NodeFilter.FILTER_ACCEPT;
        }
      }
    );
    var queue = [];
    var n;
    while ((n = walker.nextNode())) queue.push(n);

    for (var i = 0; i < queue.length; i++) {
      var textNode = queue[i];
      var parent = textNode.parentNode;
      if (!parent) continue;
      var parts = textNode.nodeValue.split(TARGET);
      var frag = document.createDocumentFragment();
      for (var j = 0; j < parts.length; j++) {
        if (parts[j]) frag.appendChild(document.createTextNode(parts[j]));
        if (j < parts.length - 1) frag.appendChild(makeLogo());
      }
      parent.replaceChild(frag, textNode);
    }
    return queue.length;
  }

  // Expose for debugging.
  window.__brandLogoReplace = replaceInBody;

  function start() {
    replaceInBody();
    // Follow theme switches (setTheme() flips data-theme on <html>).
    if (typeof MutationObserver !== 'undefined') {
      new MutationObserver(syncTheme).observe(document.documentElement, {
        attributes: true, attributeFilter: ['data-theme']
      });
    }
    // Watch the DOM for later changes (setLang() rewrites translated
    // strings, related-posts loader injects cards, etc.).
    if (typeof MutationObserver === 'undefined' || !document.body) return;
    var pending = false;
    var observer = new MutationObserver(function () {
      if (pending) return;
      pending = true;
      setTimeout(function () {
        pending = false;
        replaceInBody();
      }, 50);
    });
    observer.observe(document.body, { childList: true, subtree: true });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
