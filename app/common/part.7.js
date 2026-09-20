/* ===== مساعد الاوامر: زر عائم في كل شاشات التطبيق ولوح دردشة =====
   امر المهندس رعد 2026-09-20: «نحتاج نضيف كمان دردشة بحيث اعطيه اوامر ويعدل بدلا من الوضع
   الحالي»، واختار: زر عائم في كل الشاشات، وان تعرض الدردشة ما ستفعله وتنتظر «نفذ» قبل اي كتابة.

   كتلة مستقلة تماما: لا تلمس سطرا من القشرة ولا من اي صفحة، وتحذف بحذف هذا الجزء من
   app/common.js.parts.json وحده. المكونات كلها قائمة كما هي (chat-msg و chat-bubble من
   صفحة الفريق، و waitlist-input و waitlist-btn و chat-option-btn من الصفحة نفسها)، والالوان
   من متغيرات الثيم لا لون جديد (قاعدة التجميد 2026-09-17). */
(function () {
  "use strict";
  if (!/^\/app\//.test(String(window.location.pathname || ""))) return;

  var T = {
    ar: { title: "مساعد الاوامر", open: "افتح مساعد الاوامر", close: "اغلاق",
          hint: "اكتب امرك: «اضف مهمة متابعة عقد الايجار الخميس» او «انجز مخالفة البلدية» او «كم مخالفة مفتوحة؟»",
          ph: "اكتب امرك هنا", send: "ارسال", run: "نفذ", cancel: "الغاء", thinking: "...",
          done: "نفذ.", failed: "تعذر التنفيذ، حاول مرة اخرى.", noAnswer: "لم افهم الطلب، اعد صياغته بجملة واحدة.",
          busy: "اسرعت كثيرا، انتظر دقيقة.", off: "المساعد غير متاح الان." },
    en: { title: "Command assistant", open: "Open command assistant", close: "Close",
          hint: "Type a command: “add a task to follow up the lease on Thursday”, “complete the municipal violation”, or “how many open violations?”",
          ph: "Type your command", send: "Send", run: "Run", cancel: "Cancel", thinking: "...",
          done: "Done.", failed: "Could not run it, try again.", noAnswer: "I did not get that, rephrase it in one sentence.",
          busy: "Too fast, wait a minute.", off: "The assistant is unavailable right now." },
    fr: { title: "Assistant de commandes", open: "Ouvrir l'assistant", close: "Fermer",
          hint: "Ecrivez une commande : « ajoute une tache de suivi du bail jeudi », « termine l'amende municipale » ou « combien d'amendes ouvertes ? »",
          ph: "Ecrivez votre commande", send: "Envoyer", run: "Executer", cancel: "Annuler", thinking: "...",
          done: "Fait.", failed: "Execution impossible, reessayez.", noAnswer: "Je n'ai pas compris, reformulez en une phrase.",
          busy: "Trop vite, attendez une minute.", off: "L'assistant est indisponible." },
    ur: { title: "کمانڈ اسسٹنٹ", open: "اسسٹنٹ کھولیں", close: "بند کریں",
          hint: "حکم لکھیں: «جمعرات کو لیز کی پیروی کا کام شامل کرو» یا «بلدیہ کی خلاف ورزی مکمل کرو» یا «کتنی کھلی خلاف ورزیاں ہیں؟»",
          ph: "اپنا حکم لکھیں", send: "بھیجیں", run: "چلائیں", cancel: "منسوخ", thinking: "...",
          done: "ہو گیا۔", failed: "نہیں چل سکا، دوبارہ کوشش کریں۔", noAnswer: "سمجھ نہیں آیا، ایک جملے میں دوبارہ لکھیں۔",
          busy: "بہت تیز، ایک منٹ رکیں۔", off: "اسسٹنٹ ابھی دستیاب نہیں۔" }
  };
  function lang() {
    var l = document.documentElement.lang || "";
    if (!T[l]) { try { l = localStorage.getItem("mrzahi_lang") || "ar"; } catch (e) { l = "ar"; } }
    return T[l] ? l : "ar";
  }
  function t(k) { return (T[lang()] || T.ar)[k] || (T.ar[k] || ""); }

  var STYLE = [
    "#agentFab{position:fixed;inset-block-end:18px;inset-inline-end:18px;z-index:70;width:54px;height:54px;border-radius:50%;",
    "display:flex;align-items:center;justify-content:center;cursor:pointer;border:1px solid var(--glass-border);",
    "background:var(--primary);color:var(--btn-ink);box-shadow:0 8px 32px var(--shadow-dark);transition:transform .25s ease;}",
    "#agentFab:hover{transform:translateY(-3px);}",
    "#agentFab:focus-visible{outline:2px solid var(--primary);outline-offset:3px;}",
    "#agentFab svg{width:26px;height:26px;fill:currentColor;display:block;}",
    "#agentFab[hidden]{display:none;}",
    "#agentPanel{position:fixed;inset-block-end:84px;inset-inline-end:18px;z-index:71;width:min(380px,calc(100vw - 36px));",
    "max-height:min(620px,calc(100vh - 120px));display:flex;flex-direction:column;border-radius:24px;overflow:hidden;",
    "background:var(--glass);backdrop-filter:blur(30px) saturate(180%);-webkit-backdrop-filter:blur(30px) saturate(180%);",
    "border:1px solid var(--glass-border);box-shadow:0 8px 32px var(--shadow-dark);}",
    "#agentPanel[hidden]{display:none;}",
    "#agentHead{display:flex;align-items:center;gap:.6rem;padding:.8rem 1rem;border-bottom:1px solid var(--glass-border);}",
    "#agentHead h3{margin:0;font-size:1rem;font-weight:700;color:var(--text-primary);}",
    "#agentHead .agent-x{margin-inline-start:auto;width:32px;height:32px;border-radius:50%;border:1px solid var(--glass-border);",
    "background:transparent;color:var(--text-secondary);cursor:pointer;font:inherit;line-height:1;}",
    "#agentHead .agent-x:hover{color:var(--text-primary);border-color:var(--primary);}",
    /* فقاعات الرسائل: منسوخة كما هي من صفحة الفريق (app/team.css) */
    ".agent-messages{flex:1 1 auto;min-height:0;overflow-y:auto;padding:1rem;display:flex;flex-direction:column;gap:.5rem;}",
    ".agent-messages .chat-msg{max-width:min(86%,640px);display:grid;gap:.15rem;}",
    ".agent-messages .chat-msg.is-mine{align-self:flex-end;}",
    ".agent-messages .chat-msg.is-theirs{align-self:flex-start;}",
    ".agent-messages .chat-bubble{padding:.6rem .9rem;border-radius:18px;line-height:1.6;font-size:.95rem;white-space:pre-wrap;",
    "overflow-wrap:break-word;word-break:break-word;color:var(--text-primary);background:var(--glass-strong);border:1px solid var(--glass-border);}",
    ".agent-messages .chat-msg.is-mine .chat-bubble{background:var(--primary);color:var(--btn-ink);border-color:transparent;}",
    ".agent-hint{margin:auto;color:var(--text-tertiary);text-align:center;font-size:.85rem;line-height:1.7;}",
    ".agent-act{display:flex;gap:.5rem;flex-wrap:wrap;margin-top:.4rem;}",
    ".agent-act .waitlist-btn,.agent-act .chat-option-btn{padding:.35rem .9rem;font-size:.85rem;min-height:0;}",
    "#agentForm{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:.5rem;padding:.75rem 1rem;border-top:1px solid var(--glass-border);}",
    "@media (max-width:600px){#agentPanel{inset-inline:12px;inset-block-end:78px;width:auto;max-height:calc(100vh - 150px);}}",
    "@media print{#agentFab,#agentPanel{display:none !important;}}"
  ].join("");

  var ICON = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 2H4a2 2 0 00-2 2v18l4-4h14a2 2 0 002-2V4a2 2 0 00-2-2zM7 9h10v2H7V9zm0 4h7v2H7v-2z"/></svg>';

  var fab, panel, log, form, input, sendBtn, busy = false, pendingRow = null;

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }

  function say(who, text) {
    var hint = log.querySelector(".agent-hint");
    if (hint) hint.remove();
    var msg = el("div", "chat-msg " + (who === "me" ? "is-mine" : "is-theirs"));
    msg.appendChild(el("div", "chat-bubble", String(text || "")));
    log.appendChild(msg);
    log.scrollTop = log.scrollHeight;
    return msg;
  }

  function emptyHint() {
    log.innerHTML = "";
    log.appendChild(el("p", "agent-hint", t("hint")));
  }

  function session() {
    if (!window.mrzahiAuth || !window.mrzahiAuth.getSession) return Promise.resolve(null);
    return window.mrzahiAuth.getSession();
  }

  function post(path, payload) {
    return session().then(function (s) {
      var jwt = s && s.access_token;
      if (!jwt) return { error: "unauthorized" };
      var app = window.mrzahiApp;
      var body = { lang: lang(), org_id: (app && app.org && app.org.id) || null };
      for (var k in payload) if (Object.prototype.hasOwnProperty.call(payload, k)) body[k] = payload[k];
      return fetch(path, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json", Authorization: "Bearer " + jwt },
        body: JSON.stringify(body)
      }).then(function (r) { return r.json().catch(function () { return { error: "bad_json" }; }); });
    }).catch(function () { return { error: "network" }; });
  }

  function errorText(res) {
    if (!res) return t("failed");
    if (res.error === "rate_limited") return t("busy");
    if (res.error === "unavailable") return t("off");
    if (res.error === "no_answer" || !res.text) return t("noAnswer");
    return t("failed");
  }

  /* بعد كتابة ناجحة تعيد الشاشة رسم نفسها ان كانت تعرف كيف، فيرى اثر امره فورا */
  function refreshScreen() {
    try { if (typeof window.__dashboardRerender === "function") { window.__dashboardRerender(); return; } } catch (e) { /* تتجاهل */ }
    try { if (typeof window.__adminRefresh === "function") window.__adminRefresh(); } catch (e) { /* تتجاهل */ }
  }

  /* عرض ما سيحدث وزرا «نفذ»: لا كتابة قبل ضغطته (امر المهندس رعد 2026-09-20) */
  function offer(res) {
    var msg = say("them", res.ask || "");
    var row = el("div", "agent-act");
    var run = el("button", "waitlist-btn", t("run"));
    run.type = "button";
    var no = el("button", "chat-option-btn", t("cancel"));
    no.type = "button";
    row.appendChild(run);
    row.appendChild(no);
    msg.appendChild(row);
    pendingRow = row;
    log.scrollTop = log.scrollHeight;

    no.addEventListener("click", function () { row.remove(); pendingRow = null; });
    run.addEventListener("click", function () {
      if (busy) return;
      busy = true;
      run.disabled = true; no.disabled = true;
      post("/api/agent/confirm", { pending: res.pending }).then(function (out) {
        busy = false;
        row.remove(); pendingRow = null;
        if (out && out.done) { say("them", out.text || t("done")); refreshScreen(); }
        else say("them", errorText(out));
      });
    });
  }

  function ask(text) {
    say("me", text);
    var wait = say("them", t("thinking"));
    busy = true;
    sendBtn.disabled = true;
    post("/api/agent", { text: text }).then(function (res) {
      busy = false;
      sendBtn.disabled = false;
      wait.remove();
      if (res && res.pending && res.ask) { offer(res); return; }
      if (res && res.text) { say("them", res.text); return; }
      say("them", errorText(res));
    });
  }

  function openPanel() {
    panel.hidden = false;
    fab.setAttribute("aria-expanded", "true");
    try { input.focus(); } catch (e) { /* تتجاهل */ }
  }
  function closePanel() {
    panel.hidden = true;
    fab.setAttribute("aria-expanded", "false");
    try { fab.focus(); } catch (e) { /* تتجاهل */ }
  }

  function retitle() {
    panel.querySelector("#agentTitle").textContent = t("title");
    panel.querySelector(".agent-x").setAttribute("aria-label", t("close"));
    fab.setAttribute("aria-label", t("open"));
    fab.setAttribute("title", t("title"));
    input.setAttribute("placeholder", t("ph"));
    input.setAttribute("aria-label", t("title"));
    sendBtn.textContent = t("send");
    var hint = log.querySelector(".agent-hint");
    if (hint) hint.textContent = t("hint");
  }

  function mount() {
    if (document.getElementById("agentFab")) return;

    var style = document.createElement("style");
    style.textContent = STYLE;
    document.head.appendChild(style);

    fab = document.createElement("button");
    fab.type = "button";
    fab.id = "agentFab";
    fab.setAttribute("aria-expanded", "false");
    fab.setAttribute("aria-controls", "agentPanel");
    fab.innerHTML = ICON;

    panel = document.createElement("div");
    panel.id = "agentPanel";
    panel.hidden = true;
    panel.setAttribute("role", "dialog");
    panel.setAttribute("aria-labelledby", "agentTitle");
    panel.innerHTML =
      '<div id="agentHead"><h3 id="agentTitle"></h3>' +
      '<button type="button" class="agent-x" aria-label="">×</button></div>' +
      '<div class="agent-messages" id="agentLog" role="log" aria-live="polite"></div>' +
      '<form id="agentForm"><input type="text" class="waitlist-input" id="agentInput" autocomplete="off">' +
      '<button type="submit" class="waitlist-btn" id="agentSend"></button></form>';

    document.body.appendChild(fab);
    document.body.appendChild(panel);

    log = panel.querySelector("#agentLog");
    form = panel.querySelector("#agentForm");
    input = panel.querySelector("#agentInput");
    sendBtn = panel.querySelector("#agentSend");

    emptyHint();
    retitle();

    fab.addEventListener("click", function () { if (panel.hidden) openPanel(); else closePanel(); });
    panel.querySelector(".agent-x").addEventListener("click", closePanel);
    document.addEventListener("keydown", function (e) { if (e.key === "Escape" && !panel.hidden) closePanel(); });
    form.addEventListener("submit", function (e) {
      e.preventDefault();
      var text = String(input.value || "").trim();
      if (!text || busy) return;
      input.value = "";
      ask(text);
    });

    /* لا يكتب اسم شركة فوق الدردشة: الكتابة تتبع الشركة التي تقررها القاعدة
       (telegram_user_org) لا الشركة المفتوحة في الواجهة، فوعد باسم قد يخالف
       موضع الكتابة. يرفع هذا القيد بترحيل يجعل الكتابة تتبع المفتوحة. */

    /* تبديل اللغة يعيد كتابة نصوص اللوح (setLang يغير سمة lang على الجذر) */
    try {
      new MutationObserver(function () { retitle(); })
        .observe(document.documentElement, { attributes: true, attributeFilter: ["lang"] });
    } catch (e) { /* تتجاهل */ }
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", mount);
  else mount();
})();
