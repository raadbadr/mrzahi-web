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
      /* عبارات الهوية الست: واحدة لكل يوم بالدور، بلا تشكيل */
      var VALUES = ["عزنا باصالتنا", "عزنا بكرمنا", "عزنا بشجاعتنا",
                    "عزنا بهمتنا", "عزنا بجودنا", "عزنا برؤيتنا"];
      doc.setAttribute("data-nd-slogan", VALUES[new Date().getDate() % VALUES.length]);
      /* الراس ينمو بقدر الشريط بعد ضبط السمة، و‎syncSiteHeaderHeight‎ تكون قد قاسته
         قبلها؛ وهي مربوطة بـ‎resize‎ فنطلقه ليعاد القياس وينزل ما يعتمد عليه. */
      var again = function () { try { window.dispatchEvent(new Event("resize")); } catch (e) {} };
      again();
      window.addEventListener("load", again);
    }
  } catch (e) { /* الثيم الاصلي يبقى */ }
})();

(function () {
  var LOGO_DARK = '/mrzahi-logo-full-dark.png?v=2';
  var LOGO_LIGHT = '/mrzahi-logo-full-light.png?v=2';
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
