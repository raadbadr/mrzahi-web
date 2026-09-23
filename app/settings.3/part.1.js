    /* ============================================================
     * Settings page logic — uses window.mrzahiApp (app/common.js)
     * ============================================================ */
    (function () {
      "use strict";

      var CHANNELS = ["email", "telegram", "whatsapp", "sms"];
      var CHANNEL_KEYS = { email: "chEmail", telegram: "chTelegram", whatsapp: "chWhatsapp", sms: "chSms" };
      var OFFSETS = [60, 1440, 4320, 10080, 43200];
      var SUPPORT_EMAIL = "support@mrzahi.com";

      var app = null;
      var config = { telegramBot: null, whatsappNumber: null, smsEnabled: false, payEnabled: false };
      /* القنوات المرتبطة تظهر مطوية حتى يضغط عليها المستخدم */
      var expanded = {};
      var state = {
        loaded: false,
        linksLoaded: false,
        links: [],
        records: [],
        rules: [],
        limits: null,
        planCode: "trial",
        plans: [],
        sub: null,
        calendarUrl: ""
      };

      /* ---------- helpers ---------- */

      function el(id) { return document.getElementById(id); }

      function t(key) {
        var code = lang();
        if (translations[code] && translations[code][key]) return translations[code][key];
        if (translations.ar[key]) return translations.ar[key];
        return key;
      }

      /* Escapes the template then fills {placeholders} with already-escaped HTML fragments. */
      function fill(key, vars) {
        var out = esc(t(key));
        Object.keys(vars || {}).forEach(function (k) {
          out = out.split("{" + k + "}").join(vars[k]);
        });
        return out;
      }

      function esc(s) {
        return String(s === null || s === undefined ? "" : s)
          .replace(/&/g, "&amp;")
          .replace(/</g, "&lt;")
          .replace(/>/g, "&gt;")
          .replace(/"/g, "&quot;")
          .replace(/'/g, "&#39;");
      }

      function toast(message, kind) {
        if (app && typeof app.toast === "function") app.toast(message, kind);
      }

      function errorMessage(err) {
        if (err && err.code === "PLAN_LIMIT") return t(err.limit === "members" ? "planLimitMembers" : "planLimitItems");
        if (err && err.code === "NO_ORG") return t("noOrg");
        return t("genericError");
      }

      function show(id, on) {
        var node = el(id);
        if (node) node.style.display = on ? "" : "none";
      }

      function setMsg(id, text, kind) {
        var node = el(id);
        if (!node) return;
        node.textContent = text || "";
        node.className = "waitlist-msg" + (kind ? " " + kind : "");
        node.style.display = text ? "" : "none";
      }

      function fmtDate(iso) {
        return app && typeof app.fmtDate === "function" ? app.fmtDate(iso) : String(iso || "");
      }

      function allowedChannels() {
        /* القنوات تأتي من حدود الباقة: التجريبية Telegram فقط، والمدفوعة Telegram والبريد. */
        var list = state.limits && Array.isArray(state.limits.channels) ? state.limits.channels : ["telegram"];
        return list.length ? list : ["telegram"];
      }

      function planAllows(channel) {
        return allowedChannels().indexOf(channel) !== -1;
      }

      function linkFor(channel) {
        for (var i = 0; i < state.links.length; i++) if (state.links[i].channel === channel) return state.links[i];
        return null;
      }

      function digitsOnly(s) { return String(s || "").replace(/\D/g, ""); }

      /* ---------- profile ---------- */

      function fillProfile() {
        var p = app.profile || {};
        var user = app.user || {};
        el("fullName").value = p.full_name || "";
        el("fullNameEn").value = p.full_name_en || "";
        el("profilePhone").value = p.phone || "";
        el("profileEmail").value = p.email || user.email || "";
        var langSel = el("profileLang");
        langSel.value = p.lang || lang();
        if (!langSel.value) langSel.value = "ar";
        var tzSel = el("profileTz");
        var tz = p.tz || "Asia/Riyadh";
        var found = false;
        for (var i = 0; i < tzSel.options.length; i++) if (tzSel.options[i].value === tz) found = true;
        if (!found) {
          var opt = document.createElement("option");
          opt.value = tz;
          opt.textContent = tz;
          tzSel.appendChild(opt);
        }
        tzSel.value = tz;
        setTimeFormat(p.time_format === "12" ? "12" : "24");
      }

      /* نفس نمط رقم الجوال في بوابة إكمال الملف الشخصي (mountProfileGate في common.js) — إلزامي دائما. */
      var PHONE_RX = /^\+[1-9]\d{7,14}$/;

      function saveProfile(ev) {
        ev.preventDefault();
        var btn = el("profileSaveBtn");
        var phone = app.normalizePhone ? app.normalizePhone(el("profilePhone").value) : String(el("profilePhone").value || "").trim();
        if (!PHONE_RX.test(phone)) {
          setMsg("profileMsg", t("phoneInvalid"), "error");
          el("profilePhone").focus();
          return;
        }
        var patch = {
          full_name: el("fullName").value,
          full_name_en: el("fullNameEn").value,
          phone: phone,
          lang: el("profileLang").value,
          tz: el("profileTz").value,
          time_format: timeFormat()
        };
        btn.disabled = true;
        setMsg("profileMsg", t("saving"));
        app.updateProfile(patch).then(function () {
          if (patch.lang !== lang()) setLang(patch.lang);
          btn.disabled = false;
          el("profilePhone").value = phone;
          setMsg("profileMsg", t("profileSaved"), "success");
          toast(t("profileSaved"), "success");
        }).catch(function (err) {
          btn.disabled = false;
          setMsg("profileMsg", errorMessage(err), "error");
        });
      }

      /* ---------- notification channels ---------- */

      function loadConfig() {
        return swFetch("/api/config", { cache: "no-store", headers: { Accept: "application/json" } }, 8000)
          .then(function (res) { return res.ok ? res.json() : {}; })
          .then(function (cfg) {
            cfg = cfg || {};
            config.telegramBot = cfg.telegramBot ? String(cfg.telegramBot).replace(/^@/, "") : null;
            config.payEnabled = !!cfg.payEnabled;
            config.driveServer = !!cfg.driveServer;
            config.whatsappNumber = cfg.whatsappNumber ? String(cfg.whatsappNumber) : null;
            config.smsEnabled = !!cfg.smsEnabled;
          })
          .catch(function () { /* channels stay unavailable */ });
      }

      /* وصل المستخدم من زر «ربط حسابي» داخل البوت: اربط المحادثة بحسابه فورا ونظف الرابط */
      function linkFromBotToken() {
        var params = new URLSearchParams(window.location.search);
        var token = params.get("tglink");
        if (!token) return Promise.resolve();
        params.delete("tglink");
        var clean = window.location.pathname + (params.toString() ? "?" + params.toString() : "");
        try { window.history.replaceState(null, "", clean); } catch (e) { /* ignore */ }
        /* لا يربط بنقرة الرابط وحدها: يقرا المحادثة ثم يسال صاحب الحساب صراحة،
           فرابط ارسله غيره لا يربط حسابه بمحادثة ذلك الغير (امر 2026-09-16). */
        return app.peekTelegramLink(token).then(function (peek) {
          if (!peek || !peek.ok || !peek.chat_id) { toast(t("tgLinkFailed"), "error"); return null; }
          if (!window.confirm(t("tgLinkConfirm").split("{id}").join(String(peek.chat_id)))) {
            toast(t("tgLinkCancelled"), "error");
            return null;
          }
          return app.linkTelegramByToken(token).then(function (res) {
            if (res && res.ok) { toast(t("tgLinked"), "success"); expanded.telegram = true; }
            else toast(res && res.error === "confirm_required" ? t("tgLinkConfirmRequired") : t("tgLinkFailed"), "error");
            return reloadLinks();
          });
        }).catch(function () { toast(t("tgLinkFailed"), "error"); });
      }

      /* العودة من موافقة جوجل: الرمز الدائم صار عندنا، فنفعل الوضع وننشئ المجلد
         مرة واحدة، ثم ننظف الرابط. لا يطلب اذن جوجل بعدها ابدا. */
      function finishDriveConnect() {
        var params = new URLSearchParams(window.location.search);
        var res = params.get("drive");
        if (!res) return Promise.resolve();
        params.delete("drive");
        var clean = window.location.pathname + (params.toString() ? "?" + params.toString() : "") + window.location.hash;
        try { window.history.replaceState(null, "", clean); } catch (e) { /* ignore */ }
        if (res !== "done") {
          setMsg("storageMsg", t("storageDriveDenied"), "error");
          return Promise.resolve();
        }
        return app.updateProfile({ storage_mode: "drive" })
          .then(function () { return app.driveFolder ? app.driveFolder().catch(function () { return null; }) : null; })
          .then(function () { renderDriveSwitch(); })
          .catch(function () { setMsg("storageMsg", t("genericError"), "error"); });
      }

      function reloadLinks() {
        return app.channelLinks().then(function (rows) {
          state.links = rows || [];
          state.linksLoaded = true;
          renderChannels();
        }).catch(function (err) {
          state.linksLoaded = true;      /* حتى مع الفشل ترسم البطاقات مرة واحدة */
          renderChannels();
          toast(errorMessage(err), "error");
        });
      }

      function setStatus(channel, key, kind) {
        var node = el(channel + "Status");
        if (!node) return;
        node.textContent = t(key);
        node.className = "channel-status" + (kind ? " " + kind : "");
      }

      /* البطاقة المرتبطة تنكمش إلى صندوق صغير؛ الضغط على رأسها يفتح بيانات الربط */
      function setCollapsed(channel, linked) {
        var card = el(channel + "Card");
        if (!card) return;
        card.classList.toggle("is-linked", !!linked);
        card.classList.toggle("is-collapsed", !!linked && !expanded[channel]);
      }

      function onChannelToggle(ev) {
        if (ev.target.closest(".channel-body") || ev.target.closest("[data-action]")) return;
        var card = ev.target.closest(".feature-card.is-linked");
        if (!card) return;
        var channel = card.id.replace(/Card$/, "");
        expanded[channel] = !expanded[channel];
        setCollapsed(channel, true);
      }

      function actionBtn(action, channel, key, cls) {
        return '<button type="button" class="' + (cls || "chat-option-btn") + '" data-action="' + action +
               '" data-channel="' + channel + '">' + esc(t(key)) + "</button>";
      }

      function renderEmail() {
        var email = (app.profile && app.profile.email) || (app.user && app.user.email) || "";
        setStatus("email", "statusLinked", "success");
        el("emailBody").innerHTML =
          '<p dir="ltr">' + esc(email) + "</p>" +
          '<div class="chat-options">' + actionBtn("test", "email", "testBtn") + "</div>";
      }

      function renderCoded(channel) {
        var body = el(channel + "Body");
        var available = channel === "telegram" ? !!config.telegramBot : !!config.whatsappNumber;
        if (!available) {
          setStatus(channel, "statusUnavailable", "");
          body.innerHTML = "";
          return;
        }
        var link = linkFor(channel);
        var linked = !!(link && link.verified_at);
        var code = (link && !link.verified_at && link.verify_code) ? String(link.verify_code) : null;
        var html = "";

        if (linked) setStatus(channel, "statusLinked", "success");
        else if (code) setStatus(channel, "statusPending", "warning");
        else setStatus(channel, "statusNotLinked", "error");
        setCollapsed(channel, linked);

        if (!planAllows(channel)) html += '<p class="settings-note">' + esc(t("planChannelLocked")) + "</p>";

        if (code) {
          html += '<p class="settings-note">' + esc(t("yourCode")) + "</p>";
          html += '<div class="channel-code">' + esc(code) + "</div>";
          if (channel === "telegram") {
            html += "<p>" + fill("tgInstruction", {
              bot: '<span dir="ltr">@' + esc(config.telegramBot) + "</span>",
              command: '<span dir="ltr">/start ' + esc(code) + "</span>"
            }) + "</p>";
            /* رابط الربط رمز QR: يمسحه بكاميرا الجوال فيفتح تيليجرام على /start بالرمز مباشرة */
            html += '<div class="channel-qr" id="telegramQr" data-href="https://t.me/' +
                    encodeURIComponent(config.telegramBot) + "?start=" + encodeURIComponent(code) + '">' +
                    '<div class="channel-qr-img" id="telegramQrImg" aria-hidden="true"></div>' +
                    '<p class="settings-note">' + esc(t("tgQrHint")) + "</p></div>";
          } else {
            html += "<p>" + fill("waInstruction", {
              code: '<span dir="ltr">' + esc(code) + "</span>",
              number: '<span dir="ltr">+' + esc(digitsOnly(config.whatsappNumber)) + "</span>"
            }) + "</p>";
            html += '<div class="chat-options"><a class="chat-option-btn" target="_blank" rel="noopener" href="https://wa.me/' +
                    digitsOnly(config.whatsappNumber) + "?text=" + encodeURIComponent(code) + '">' +
                    esc(t("openWhatsapp")) + "</a></div>";
          }
        }

        html += '<div class="chat-options">';
        if (!linked) html += actionBtn("code", channel, code ? "regenCodeBtn" : "genCodeBtn", "waitlist-btn");
        if (code) html += actionBtn("refresh", channel, "refreshBtn");
        if (linked) html += actionBtn("test", channel, "testBtn", "waitlist-btn");
        if (link) html += actionBtn("unlink", channel, "unlinkBtn");
        html += "</div>";
        body.innerHTML = html;
        renderTelegramQr(body);
      }

      /* يرسم رمز QR لرابط t.me الموجود في البطاقة؛ إن لم تحمل المكتبة تزال الحاوية بصمت */
      function renderTelegramQr(body) {
        var box = el("telegramQr"), img = el("telegramQrImg");
        if (!box || !img) return;
        var href = box.getAttribute("data-href");
        if (!href || typeof qrcode !== "function") { box.remove(); return; }
        try {
          var q = qrcode(0, "M");
          q.addData(href);
          q.make();
          img.innerHTML = q.createSvgTag({ cellSize: 4, margin: 0, scalable: true });
        } catch (err) { box.remove(); }
      }

      function renderSms() {
        var body = el("smsBody");
        if (!config.smsEnabled) {
          setStatus("sms", "statusUnavailable", "");
          body.innerHTML = "";
          return;
        }
        var link = linkFor("sms");
        var linked = !!(link && link.verified_at && link.external_id);
        setStatus("sms", linked ? "statusLinked" : "statusNotLinked", linked ? "success" : "error");
        var html = "";
        if (!planAllows("sms")) html += '<p class="settings-note">' + esc(t("planChannelLocked")) + "</p>";
        if (linked) html += '<p dir="ltr">' + esc(link.external_id) + "</p>";
        html += '<form class="waitlist-form" data-action="sms-link" novalidate>' +
                '<input type="tel" class="waitlist-input" id="smsPhone" placeholder="' + esc(t("smsPhonePlaceholder")) +
                '" autocomplete="tel" inputmode="tel" dir="ltr" aria-label="' + esc(t("smsPhoneLabel")) +
                '" value="' + esc(linked ? link.external_id : "") + '">' +
                '<button type="submit" class="waitlist-btn">' + esc(t("linkBtn")) + "</button></form>";
        html += '<div class="chat-options">';
        if (linked) html += actionBtn("test", "sms", "testBtn", "waitlist-btn");
        if (link) html += actionBtn("unlink", "sms", "unlinkBtn");
        html += "</div>";
        body.innerHTML = html;
      }

      function renderChannels() {
        /* القنوات بيانات: لا ترسم قبل وصول حدود الباقة وروابط المستخدم */
        if (!state.loaded || !state.limits || !state.linksLoaded) return;
        /* لا نعرض إلا القنوات التي تسمح بها الباقة (حاليا Telegram وحده). */
        var allowed = allowedChannels();
        CHANNELS.forEach(function (ch) {
          var card = document.getElementById(ch + "Card");
          if (card) card.hidden = allowed.indexOf(ch) === -1;
        });
        renderEmail();
        renderCoded("telegram");
        renderCoded("whatsapp");
        renderSms();
      }

      function testResultMessage(res) {
        if (res && res.ok) return { text: t("testSent"), kind: "success" };
        var code = res && res.error ? String(res.error) : "";
        if (code === "channel_not_linked") return { text: t("testNotLinked"), kind: "error" };
        if (code === "send_failed" || code === "unknown_channel") return { text: t("testFailed"), kind: "error" };
        return { text: t("genericError"), kind: "error" };
      }

      function onChannelAction(ev) {
        var btn = ev.target.closest("[data-action]");
        if (!btn || btn.tagName === "FORM") return;
        var action = btn.getAttribute("data-action");
        var channel = btn.getAttribute("data-channel");
        if (!action || !channel) return;
        btn.disabled = true;

        if (action === "code") {
          app.requestChannelCode(channel).then(function () {
            toast(t("codeGenerated"), "success");
            return reloadLinks();
          }).catch(function (err) { btn.disabled = false; toast(errorMessage(err), "error"); });
        } else if (action === "refresh") {
          reloadLinks().then(function () { btn.disabled = false; toast(t("refreshed"), "success"); });
        } else if (action === "test") {
          toast(t("testSending"));
          app.testChannel(channel).then(function (res) {
            btn.disabled = false;
            var m = testResultMessage(res);
            toast(m.text, m.kind);
          }).catch(function () { btn.disabled = false; toast(t("testFailed"), "error"); });
        } else if (action === "unlink") {
          app.unlinkChannel(channel).then(function () {
            toast(t("unlinked"), "success");
            return reloadLinks();
          }).catch(function (err) { btn.disabled = false; toast(errorMessage(err), "error"); });
        } else {
          btn.disabled = false;
        }
      }

      function onSmsSubmit(ev) {
        var form = ev.target.closest('form[data-action="sms-link"]');
        if (!form) return;
        ev.preventDefault();
        var input = el("smsPhone");
        var phone = String(input ? input.value : "").replace(/[\s\-().]/g, "");
        if (/^00\d+$/.test(phone)) phone = "+" + phone.slice(2);
        if (!/^\+[1-9]\d{7,14}$/.test(phone)) {
          toast(t("invalidPhone"), "error");
          if (input) input.focus();
          return;
        }
        var submit = form.querySelector("button[type=submit]");
        if (submit) submit.disabled = true;
        app.setSmsPhone(phone).then(function () {
          toast(t("phoneLinked"), "success");
          return reloadLinks();
        }).catch(function (err) {
          if (submit) submit.disabled = false;
          toast(err && err.message === "invalid phone" ? t("invalidPhone") : errorMessage(err), "error");
        });
      }

      /* ---------- reminder rules ---------- */

      function loadRules() {
        if (!app.org) { renderRules(); return Promise.resolve(); }
        return Promise.all([app.listRecords(), app.listRules()]).then(function (res) {
          state.records = res[0] || [];
          state.rules = res[1] || [];
          renderRules();
        }).catch(function (err) {
          el("rulesWrap").innerHTML = '<p class="waitlist-msg error">' + esc(errorMessage(err)) + "</p>";
        });
      }

      /* Record-level rule (item_id null); rules come newest first so the first match wins. */
      /* كل قواعد السجل مرتبة من الابعد الى الاقرب */
      function rulesForRecord(recordId) {
        var out = [];
        (state.rules || []).forEach(function (r) {
          if (r.record_id === recordId && !r.item_id) out.push(r);
        });
        out.sort(function (a, b) { return (Number(b.offset_minutes) || 0) - (Number(a.offset_minutes) || 0); });
        return out;
      }

      function ruleForRecord(recordId) {
        for (var i = 0; i < state.rules.length; i++) {
          var r = state.rules[i];
          if (r.record_id === recordId && !r.item_id) return r;
        }
        return null;
      }

      function offsetLabel(minutes) {
        return OFFSETS.indexOf(minutes) !== -1 ? t("off" + minutes) : t("offCustom").replace("{n}", String(minutes));
      }

      function renderRules() {
        var wrap = el("rulesWrap");
        if (!wrap) return;
        if (!app.org) { wrap.innerHTML = '<p class="waitlist-msg error">' + esc(t("noOrg")) + "</p>"; return; }
        if (!state.records.length) { wrap.innerHTML = "<p>" + esc(t("noRecords")) + "</p>"; return; }
        var allowed = allowedChannels();
        var html = '<div class="table-wrap"><table class="rules-table"><thead><tr>' +
          "<th>" + esc(t("colRecord")) + "</th>" +
          "<th>" + esc(t("colOffset")) + "</th>" +
          "<th>" + esc(t("colChannels")) + "</th>" +
          "<th>" + esc(t("colTarget")) + "</th>" +
          "<th>" + esc(t("colActions")) + "</th>" +
          "</tr></thead><tbody>";

        state.records.forEach(function (record) {
          /* قواعد السجل كلها لا واحدة: صاحبه قد يريد التذكير قبل شهر وقبل
             اسبوع وقبل يوم معا (المهندس رعد 2026-09-17). */
          var rules = rulesForRecord(record.id);
          var rule = rules[0] || null;
          var chosen = rules.map(function (r) { return Number(r.offset_minutes) || 1440; });
          if (!chosen.length) chosen = [1440];
          var channels = rule && Array.isArray(rule.channels) ? rule.channels : ["telegram"];
          var target = rule && rule.target === "all" ? "all" : "assignee";
          var offsets = OFFSETS.slice();
          chosen.forEach(function (o) { if (offsets.indexOf(o) === -1) offsets.push(o); });
          offsets.sort(function (a, b) { return b - a; });

          html += '<tr data-record="' + esc(record.id) + '"' + (rule ? ' data-rule="' + esc(rule.id) + '"' : "") + ">";
          html += '<td><span class="highlight">' + esc(record.name) + "</span>" +
                  (rule ? ' <span class="settings-note" style="color:var(--success)">' + esc(t("ruleActive")) + "</span>" : "") + "</td>";
          /* اكثر من موعد لكل سجل: مربعات لا قائمة واحدة، بالمكون نفسه الذي
             تستعمله القنوات (rule-check) فلا شكل جديد. */
          html += '<td><div class="rule-channels rule-offsets">';
          offsets.forEach(function (o) {
            html += '<label class="rule-check"><input type="checkbox" class="rule-offset" value="' + o + '"' +
                    (chosen.indexOf(o) !== -1 ? " checked" : "") + "><span>" + esc(offsetLabel(o)) + "</span></label>";
          });
          html += "</div></td>";
          html += '<td><div class="rule-channels">';
          CHANNELS.forEach(function (ch) {
            var on = channels.indexOf(ch) !== -1;
            var ok = allowed.indexOf(ch) !== -1;
            html += '<label class="rule-check"><input type="checkbox" class="rule-channel" value="' + ch + '"' +
                    (on && ok ? " checked" : "") + (ok ? "" : " disabled") + "><span>" + esc(t(CHANNEL_KEYS[ch])) + "</span></label>";
          });
          html += "</div></td>";
          html += '<td><select class="waitlist-input rule-target">' +
                  '<option value="assignee"' + (target === "assignee" ? " selected" : "") + ">" + esc(t("targetAssignee")) + "</option>" +
                  '<option value="all"' + (target === "all" ? " selected" : "") + ">" + esc(t("targetAll")) + "</option>" +
                  "</select></td>";
          /* رموز لا كلمات، على سطر واحد، والحذف احمر بسلة (امر المهندس رعد
             2026-09-17: «غير دي الى رموز، الحفظ ايقونة حفظ، والحذف زبالة
             بالاحمر، وحطهم على سطر واحد»). الاسم يبقى في التلميح ولقارئ
             الشاشة، والمكون هو chat-option-btn is-icon القائم في المنصة. */
          html += '<td><div class="row-actions chat-options">' +
                  '<button type="button" class="chat-option-btn is-icon" data-rule-action="save"' +
                    ' title="' + esc(t("saveRuleBtn")) + '" aria-label="' + esc(t("saveRuleBtn")) + '">' + RULE_ICON.save + "</button>" +
                  (rule ? '<button type="button" class="chat-option-btn is-icon is-danger" data-rule-action="delete"' +
                    ' title="' + esc(t("deleteRuleBtn")) + '" aria-label="' + esc(t("deleteRuleBtn")) + '">' + RULE_ICON.trash + "</button>" : "") +
                  "</div></td>";
          html += "</tr>";
        });

        html += "</tbody></table></div>";
        wrap.innerHTML = html;
      }

      /* ايقونتا الصف: من مجموعة المنصة نفسها (صفحة المستندات) لا رسم جديد */
      var RULE_ICON = {
        save: '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M17 3H5a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2V7l-4-4zm-5 16a3 3 0 110-6 3 3 0 010 6zm3-10H5V5h10v4z"/></svg>',
        trash: '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M6 19a2 2 0 002 2h8a2 2 0 002-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>'
      };

      function onRuleAction(ev) {
        var btn = ev.target.closest("[data-rule-action]");
        if (!btn) return;
        var row = btn.closest("tr[data-record]");
        if (!row) return;
        var action = btn.getAttribute("data-rule-action");
        var recordId = row.getAttribute("data-record");
        var ruleId = row.getAttribute("data-rule") || null;
        var allowed = allowedChannels();

        if (action === "save") {
          var channels = [];
          row.querySelectorAll(".rule-channel").forEach(function (cb) {
            if (cb.checked && !cb.disabled && allowed.indexOf(cb.value) !== -1) channels.push(cb.value);
          });
          if (!channels.length) channels = ["telegram"];
          btn.disabled = true;
          var offsets = [];
          row.querySelectorAll(".rule-offset").forEach(function (cb) {
            if (cb.checked) offsets.push(Number(cb.value));
          });
          if (!offsets.length) offsets = [1440];
          app.saveRules(recordId, offsets, channels, row.querySelector(".rule-target").value)
          .then(function () {
            toast(t("ruleSaved"), "success");
            return loadRules();
          }).catch(function (err) { btn.disabled = false; toast(errorMessage(err), "error"); });
        } else if (action === "delete" && recordId) {
          /* الحذف دائما عليه تاكيد، بحوار المنصة لا بنافذة المتصفح (امره نفسه) */
          var ask = app.confirmDanger
            ? app.confirmDanger(t("deleteRuleBtn"), { warn: t("deleteRuleConfirm") })
            : Promise.resolve(window.confirm(t("deleteRuleConfirm")));
          ask.then(function (ok) {
            if (!ok) return;
            btn.disabled = true;
            app.deleteRules(recordId).then(function () {
              toast(t("ruleDeleted"), "success");
              return loadRules();
            }).catch(function (err) { btn.disabled = false; toast(errorMessage(err), "error"); });
          });
        }
      }

      /* ---------- calendar ---------- */

      /* ---------- API keys ---------- */
      function renderApiKeys(rows) {
        var box = el("apiKeyList");
        rows = rows || [];
        box.hidden = !rows.length;
        if (!rows.length) { setMsg("apiMsg", t("apiNone")); return; }
        box.innerHTML = rows.map(function (k) {
          /* سطر أول: اسم المنصة ومقدمة مفتاحها. سطر ثان باهت: التواريخ بصيغة واحدة يوم-شهر-سنة */
          var meta = esc(t("apiCreatedOn")) + " " + esc(app.fmtDate(k.created_at)) +
                     (k.last_used_at ? " · " + esc(t("apiLastUsed")) + " " + esc(app.fmtDate(k.last_used_at, { withTime: true })) : "");
          return '<div class="platform-stat-detail-row">' +
                 '<span class="api-key-id"><b>' + esc(k.name) + '</b> <code dir="ltr">' + esc(k.prefix) + '…</code>' +
                 '<span class="settings-note">' + meta + "</span></span>" +
                 '<span class="platform-stat-detail-val"><button type="button" class="chat-option-btn is-danger" data-revoke-key="' + esc(k.id) + '">' + esc(t("apiRevoke")) + "</button></span></div>";
        }).join("");
      }
      function loadApiKeys() {
        return app.apiKeys().then(renderApiKeys).catch(function (err) { setMsg("apiMsg", errorMessage(err), "error"); });
      }
      function wireApi() {
        var card = el("apiCard"); if (!card) return;
        var role = app.role ? app.role() : "";
        if (role !== "owner" && role !== "admin") { card.hidden = true; return; }
        el("apiKeyCreateBtn").addEventListener("click", function () {
          var btn = this; btn.disabled = true;
          app.createApiKey(el("apiKeyName").value).then(function (res) {
            el("apiKeyValue").value = res && res.key ? res.key : "";
            el("apiKeyReveal").hidden = false;
            setMsg("apiMsg", t("apiCreated"), "success");
            el("apiKeyName").value = "";
            return loadApiKeys();
          }).catch(function (err) { setMsg("apiMsg", errorMessage(err), "error"); })
            .finally(function () { btn.disabled = false; });
        });
        el("apiKeyCopyBtn").addEventListener("click", function () {
          var v = el("apiKeyValue").value; if (!v) return;
          var ok = function () { toast(t("urlCopied"), "success"); };
          if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(v).then(ok, ok);
          else { el("apiKeyValue").select(); try { document.execCommand("copy"); } catch (e) { /* ignore */ } ok(); }
        });
        el("apiKeyList").addEventListener("click", function (ev) {
          var b = ev.target.closest("[data-revoke-key]"); if (!b) return;
          b.disabled = true;
          app.revokeApiKey(b.getAttribute("data-revoke-key")).then(function () { setMsg("apiMsg", t("apiRevoked"), "success"); return loadApiKeys(); })
            .catch(function (err) { b.disabled = false; setMsg("apiMsg", errorMessage(err), "error"); });
        });
        loadApiKeys();
      }

      /* ---------- الربط المحاسبي (امر المهندس رعد 2026-09-23) ----------
         المصاريف والفواتير ترسل مسودات الى المنصة المحاسبية التي يختارها العميل، والبداية
         بقيود. المفتاح يذهب الى الوركر وحده فيتحقق منه عند المنصة ويحفظه مشفرا، ولا يعود
         الى المتصفح ابدا. البطاقة للمالك والمشرف في حساب منشاة، وتظهر مرة واحدة بعد وصول
         حالتها (قاعدة الثبات). */
      var ACCT_PROVIDERS = [{ value: "qoyod", key: "acctProviderQoyod" }];
      var ACCT_WAIT = { no_inventory: "acctWaitInventory", no_expense_account: "acctWaitAccount", no_vendor: "acctWaitVendor",
                        no_amount: "acctWaitAmount", no_customer: "acctWaitCustomer", no_sales_product: "acctWaitProduct" };
      var ACCT_ERR = { invalid_key: "acctErrKey", not_admin: "acctErrAdmin", rate_limited: "acctErrRate",
                       provider_error: "acctErrProvider", not_connected: "acctErrNotConnected" };
      var acct = { status: null, lookups: null };

      /* نداء الوركر بجلسة صاحبه وبمهلة: لا انتظار ابدي (قاعدة 17) */
      function acctPost(path, body) {
        var auth = window.mrzahiAuth;
        var ctrl = window.AbortController ? new AbortController() : null;
        var timer = setTimeout(function () { if (ctrl) ctrl.abort(); }, 35000);
        return Promise.resolve(auth && auth.getSession ? auth.getSession() : null).then(function (sess) {
          var headers = { "Content-Type": "application/json" };
          if (sess && sess.access_token) headers.Authorization = "Bearer " + sess.access_token;
          return fetch(path, { method: "POST", headers: headers, body: JSON.stringify(body || {}), signal: ctrl ? ctrl.signal : undefined });
        }).then(function (res) {
          clearTimeout(timer);
          return res.json().catch(function () { return {}; }).then(function (data) {
            if (!res.ok) { var e = new Error((data && data.error) || "failed"); e.code = (data && data.error) || "failed"; throw e; }
            return data || {};
          });
        }, function (err) { clearTimeout(timer); throw err; });
      }
      function acctError(err) { return t(ACCT_ERR[err && err.code] || "genericError"); }
      function acctProviderName(v) {
        var hit = ACCT_PROVIDERS.filter(function (p) { return p.value === v; })[0];
        return hit ? t(hit.key) : String(v || "");
      }
      function acctFill(id, rows, value, firstKey) {
        var sel = el(id); if (!sel) return;
        var html = (firstKey ? '<option value="">' + esc(t(firstKey)) + "</option>" : "") +
          (rows || []).map(function (r) {
            return '<option value="' + esc(r.value) + '">' + esc(r.label) + "</option>";
          }).join("");
        if (sel.innerHTML !== html) sel.innerHTML = html;
        sel.value = value == null ? "" : String(value);
        if (sel.value !== (value == null ? "" : String(value))) sel.value = "";
      }
      function renderAcct() {
        var card = el("acctCard"); if (!card) return;
        var st = acct.status || {};
        el("acctConnectBox").hidden = !!st.connected;
        el("acctLinkedBox").hidden = !st.connected;
        if (!st.connected) {
          acctFill("acctProvider", ACCT_PROVIDERS.map(function (p) { return { value: p.value, label: t(p.key) }; }), (el("acctProvider") && el("acctProvider").value) || "qoyod");
          card.hidden = false;
          return;
        }
        var s = st.settings || {};
        el("acctLinkedLine").textContent = t("acctLinkedLine")
          .split("{provider}").join(acctProviderName(st.provider))
          .split("{hint}").join(st.key_hint || "")
          .split("{date}").join(fmtDate(st.connected_at));
        var lk = acct.lookups || {};
        var pick = function (rows) { return (rows || []).map(function (r) { return { value: r.id, label: r.code ? r.code + " " + r.name : r.name }; }); };
        acctFill("acctInventory", pick(lk.inventories), s.inventory_id, "acctPick");
        acctFill("acctExpenseAccount", pick(lk.expense_accounts), s.expense_account_id, "acctPick");
        acctFill("acctExpenseTax", [{ value: "inclusive15", label: t("acctTaxInclusive") }, { value: "exempt", label: t("acctTaxExempt") }], s.expense_tax || "inclusive15");
        acctFill("acctVendor", pick(lk.vendors), s.default_vendor_id, "acctNone");
        acctFill("acctProduct", pick(lk.products), s.sales_product_id, "acctNone");
        /* الارقام: ما ارسل، وما ينتظر ولماذا، وما تعذر وآخر خطئه */
        var c = st.counts || {}, rows = [];
        var row = function (label, value) {
          return '<div class="platform-stat-detail-row"><span>' + esc(label) + '</span><span class="platform-stat-detail-val">' + esc(String(value)) + "</span></div>";
        };
        if (c.sent) rows.push(row(t("acctCountSent"), c.sent));
        Object.keys(st.waiting || {}).forEach(function (reason) {
          rows.push(row(t(ACCT_WAIT[reason] || "acctCountWaiting"), st.waiting[reason]));
        });
        if (c.failed) rows.push(row(t("acctCountFailed"), c.failed));
        if (st.last_error) rows.push(row(t("acctLastError"), st.last_error));
        var box = el("acctCounts");
        var html = rows.join("");
        if (box.innerHTML !== html) box.innerHTML = html;
        box.hidden = !rows.length;
        card.hidden = false;
      }
      function acctLoadStatus() {
        if (!app.org || !app.client) return Promise.resolve();
        return app.client.rpc("acct_link_status", { p_org: app.org.id }).then(function (res) {
          if (res && res.error) throw res.error;
          acct.status = (res && res.data) || { connected: false };
          if (acct.status.connected && !acct.lookups) {
            return acctPost("/api/accounting/lookups", { org: app.org.id })
              .then(function (d) { acct.lookups = d.lookups || null; })
              .catch(function (err) { setMsg("acctMsg", acctError(err), "error"); });
          }
        }).then(renderAcct);
      }
      function acctSettingsFromForm() {
        var v = function (id) { var n = el(id); return n && n.value ? n.value : null; };
        return { inventory_id: v("acctInventory"), expense_account_id: v("acctExpenseAccount"), expense_tax: v("acctExpenseTax") || "inclusive15",
                 default_vendor_id: v("acctVendor"), sales_product_id: v("acctProduct") };
      }
      function wireAccounting() {
        var card = el("acctCard"); if (!card) return;
        var role = app.role ? app.role() : "";
        var ent = app.org && app.org.entity_type;
        if (!app.org || (role !== "owner" && role !== "admin") || ent === "individual") { card.hidden = true; return; }
        el("acctConnectBtn").addEventListener("click", function () {
          var btn = this, key = String(el("acctKey").value || "").trim();
          if (!key) { el("acctKey").focus(); return; }
          btn.disabled = true;
          setMsg("acctMsg", "");
          acctPost("/api/accounting/connect", { org: app.org.id, provider: el("acctProvider").value || "qoyod", key: key }).then(function (d) {
            el("acctKey").value = "";
            acct.lookups = d.lookups || null;
            return acctLoadStatus().then(function () {
              var s = (acct.status && acct.status.settings) || {};
              setMsg("acctMsg", t(s.expense_account_id ? "acctConnected" : "acctNeedAccount"), "success");
            });
          }).catch(function (err) { setMsg("acctMsg", acctError(err), "error"); })
            .then(function () { btn.disabled = false; });
        });
        el("acctSaveBtn").addEventListener("click", function () {
          var btn = this; btn.disabled = true;
          acctPost("/api/accounting/settings", { org: app.org.id, settings: acctSettingsFromForm() }).then(function () {
            return acctLoadStatus().then(function () { setMsg("acctMsg", t("acctSaved"), "success"); });
          }).catch(function (err) { setMsg("acctMsg", acctError(err), "error"); })
            .then(function () { btn.disabled = false; });
        });
        el("acctSyncBtn").addEventListener("click", function () {
          var btn = this; btn.disabled = true;
          acctPost("/api/accounting/sync", { org: app.org.id }).then(function (d) {
            var sm = (d && d.summary) || {};
            return acctLoadStatus().then(function () {
              setMsg("acctMsg", t("acctSyncDone").split("{sent}").join(String(sm.sent || 0))
                .split("{waiting}").join(String(sm.waiting || 0)).split("{failed}").join(String(sm.failed || 0)), sm.failed ? "error" : "success");
            });
          }).catch(function (err) { setMsg("acctMsg", acctError(err), "error"); })
            .then(function () { btn.disabled = false; });
        });
        /* فك الربط لا يمضي بنقرة: حوار المنصة يسمي ما سيقع، والالغاء هو الافتراضي */
        el("acctForgetBtn").addEventListener("click", function () {
          var btn = this;
          var ask = app.confirmDanger
            ? app.confirmDanger(t("acctForget"), { warn: t("acctForgetConfirm") })
            : Promise.resolve(window.confirm(t("acctForgetConfirm")));
          ask.then(function (yes) {
            if (!yes) return;
            btn.disabled = true;
            acctPost("/api/accounting/forget", { org: app.org.id }).then(function () {
              acct.lookups = null;
              return acctLoadStatus().then(function () { setMsg("acctMsg", t("acctForgotten"), "success"); });
            }).catch(function (err) { setMsg("acctMsg", acctError(err), "error"); })
              .then(function () { btn.disabled = false; });
          });
        });
        acctLoadStatus().catch(function (err) { setMsg("acctMsg", acctError(err), "error"); renderAcct(); });
      }

      function loadCalendar() {
        if (!app.org) {
          setMsg("calendarMsg", t("noOrg"), "error");
          el("copyUrlBtn").disabled = true;
          el("regenerateBtn").disabled = true;
          return Promise.resolve();
        }
        return app.calendarUrl().then(function (url) {
          state.calendarUrl = url;
          el("calendarUrl").value = url;
          syncCalendarLinks(url);
        }).catch(function (err) {
          /* بلا رابط: الازرار تعطل بدل ان تبقى href="#" فتفتح تبويبا على
             الصفحة نفسها ويظن المستخدم الموقع مكسورا (المهندس رعد 2026-09-16). */
          ["googleCalBtn", "appleCalBtn", "copyUrlBtn", "regenerateBtn"].forEach(function (id) {
            var n = el(id);
            if (!n) return;
            n.setAttribute("aria-disabled", "true");
            n.style.pointerEvents = "none";
            n.style.opacity = ".5";
          });
          setMsg("calendarMsg", errorMessage(err), "error");
        });
      }

      /* صيغة الوقت: مفتاح بزرين، ومثال حي تحته يريه الفرق قبل أن يحفظ */
      function timeFormat() {
        var on = document.querySelector("#profileTimeFormat .cal-mode.is-active");
        return on && on.getAttribute("data-time-format") === "12" ? "12" : "24";
      }
      function setTimeFormat(value) {
        var box = el("profileTimeFormat");
        if (!box) return;
        var btns = box.querySelectorAll(".cal-mode");
        for (var i = 0; i < btns.length; i++) {
          btns[i].classList.toggle("is-active", btns[i].getAttribute("data-time-format") === value);
          btns[i].setAttribute("aria-pressed", btns[i].getAttribute("data-time-format") === value ? "true" : "false");
        }
        var sample = el("timeFormatSample");
        if (sample) {
          var d = new Date();
          d.setHours(21, 30, 0, 0);
          sample.textContent = new Intl.DateTimeFormat("en-GB", { numberingSystem: "latn", hour: value === "12" ? "numeric" : "2-digit", minute: "2-digit", hour12: value === "12" }).format(d);
        }
      }

      function copyDeviceUrl() {
        var input = el("deviceUrl");
        var url = input ? input.value : "";
        if (!url) return;
        var done = function () { setMsg("calendarMsg", t("urlCopied"), "success"); toast(t("urlCopied"), "success"); };
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(url).then(done).catch(function () { input.focus(); input.select(); });
        } else { input.focus(); input.select(); }
      }

      function copyCalendarUrl() {
        var url = state.calendarUrl || el("calendarUrl").value;
        if (!url) return;
        var done = function () { setMsg("calendarMsg", t("urlCopied"), "success"); toast(t("urlCopied"), "success"); };
        var fallback = function () {
          try {
            var input = el("calendarUrl");
            input.focus();
            input.select();
            input.setSelectionRange(0, url.length);
            if (document.execCommand("copy")) { done(); return; }
          } catch (e) { /* fall through */ }
          setMsg("calendarMsg", t("copyFailed"), "error");
        };
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(url).then(done).catch(fallback);
        } else {
          fallback();
        }
      }

      function regenerateCalendar() {
        if (!window.confirm(t("regenerateConfirm"))) return;
        var btn = el("regenerateBtn");
        btn.disabled = true;
        app.regenerateCalendarToken().then(function (token) {
          state.calendarUrl = window.location.origin + "/api/calendar/" + token + ".ics";
          syncCalendarLinks(state.calendarUrl);
          el("calendarUrl").value = state.calendarUrl;
          btn.disabled = false;
          setMsg("calendarMsg", t("calendarRegenerated"), "success");
          toast(t("calendarRegenerated"), "success");
        }).catch(function (err) {
          btn.disabled = false;
          setMsg("calendarMsg", errorMessage(err), "error");
        });
      }

      /* ---------- subscription ---------- */

      function loadSubscription() {
        if (!app.org) { renderSubscription(); return Promise.resolve(); }
        return Promise.all([app.effectivePlan(), app.plans(), app.subscription()]).then(function (res) {
          state.planCode = res[0] || "trial";
          state.plans = res[1] || [];
          state.sub = res[2] || null;
          var plan = currentPlan();
          state.limits = plan && plan.limits ? plan.limits : { channels: ["telegram"] };
          renderSubscription();
        }).catch(function (err) {
          state.limits = { channels: ["telegram"] };
          el("planSummary").innerHTML = '<li><span class="waitlist-msg error">' + esc(errorMessage(err)) + "</span></li>";
        });
      }

      /* طلب معلق لا يمر بـ catch: بلا مهلة تبقى بطاقات القنوات فارغة بلا سبب ظاهر. */
      function swFetch(url, opts, ms) {
        var o = Object.assign({}, opts || {});
        var ctrl = window.AbortController ? new AbortController() : null;
        if (ctrl) o.signal = ctrl.signal;
        var timer = setTimeout(function () { if (ctrl) ctrl.abort(); }, ms || 8000);
        return fetch(url, o).then(function (r) { clearTimeout(timer); return r; },
          function (e) { clearTimeout(timer); throw e; });
      }

      /* ---------- التخزين: حصة المنصة وخيار درايف ---------- */

      function fmtMb(mb) {
        if (mb >= 1024) return (mb / 1024).toFixed(1) + " GB";
        return (mb < 10 ? mb.toFixed(1) : String(Math.round(mb))) + " MB";
      }

      /* رقم الحصة يكتب من اخر قيمة وصلت لا من طلب جديد، فيعاد بلغة الواجهة عند
         تبديل اللغة («غير محدود») بلا نداء شبكة وبلا ومضة (قاعدة الثبات). */
      var storageUsedBytes = null;

      function paintStorageValue() {
        var value = el("storageUsageValue");
        if (!value || storageUsedBytes === null) return;
        var capMb = state.limits ? state.limits.storage_mb : null;
        var capText = (capMb === null || capMb === undefined) ? t("unlimited") : fmtMb(Number(capMb));
        value.textContent = fmtMb(storageUsedBytes / 1048576) + " / " + capText;
      }

      function renderStorage() {
        var value = el("storageUsageValue");
        if (!value) return Promise.resolve();
        renderDriveSwitch();
        if (!app.org || typeof app.storageUsed !== "function") { value.textContent = "—"; return Promise.resolve(); }
        var capMb = state.limits ? state.limits.storage_mb : null;
        return app.storageUsed().then(function (used) {
          var usedMb = (Number(used) || 0) / 1048576;
          storageUsedBytes = Number(used) || 0;
          paintStorageValue();
          var pct = capMb ? Math.min(100, Math.round(usedMb / Number(capMb) * 100)) : 0;
          var fill = el("storageBarFill");
          if (fill) fill.style.width = pct + "%";
          if (pct >= 90) setMsg("storageMsg", t("storageFull"), "error"); else show("storageMsg", false);
        }).catch(function () { value.textContent = "—"; });
      }

      /* خياران صريحان لا مفتاح واحد: «عندنا» و«درايف»، والمختار عليه علامة،
         والمجلد الحقيقي في درايف يكتب باسمه ورابطه (امر المهندس رعد 2026-09-16). */
      function renderDriveSwitch() {
        var box = el("storagePick");
        if (!box) return;
        var optPlatform = box.querySelector('[data-store-pick="platform"]');
        var optDrive = box.querySelector('[data-store-pick="drive"]');
        var status = el("storageDriveStatus");
        /* تخزين المنشاة قرار مالك او مشرف منذ 2026-09-16: القاعدة ترفض غيرهما
           بـ not_admin، فلا يعرض عليه خيار يوهمه انه يملكه. */
        var mayDrive = !(app.isOrgAdmin && !app.isOrgAdmin());
        var available = !!(app.driveOAuthAvailable && app.driveOAuthAvailable()) && mayDrive;
        var on = !!(app.profile && app.profile.storage_mode === "drive") && available;
        if (optDrive) {
          optDrive.disabled = !available;
          optDrive.classList.toggle("is-on", on);
          optDrive.setAttribute("aria-pressed", on ? "true" : "false");
        }
        if (optPlatform) {
          optPlatform.classList.toggle("is-on", !on);
          optPlatform.setAttribute("aria-pressed", !on ? "true" : "false");
        }
        if (status) status.textContent = !mayDrive ? t("storageDriveAdminOnly") : (!available ? t("storageDriveUnavailable") : (on ? t("storageDriveOn") : ""));
        var link = el("storageDriveFolderLink");
        var f = on && app.driveFolderCached ? app.driveFolderCached() : null;
        if (link) { link.hidden = !f; if (f) { link.href = f.url; link.textContent = f.path; link.title = t("storageDriveFolder"); } }
        var countEl = el("storageDriveCount");
        if (countEl) {
          countEl.hidden = true;
          if (f && app.driveFolderFileCount) {
            app.driveFolderFileCount(f.id).then(function (n) {
              if (!on || el("storageDriveCount") !== countEl) return;
              countEl.textContent = t("storageDriveCount").replace("{n}", String(n));
              countEl.hidden = false;
            }).catch(function () { /* المجلد فارغ أو تعذر العد: يبقى العدد مخفيا بلا رسالة خطأ */ });
          }
        }
      }

      /* التفويض يطلب بنقرة المستخدم نفسها، ولا يحفظ الخيار إلا بعد الإذن */
      function onDriveToggle(ev) {
        var opt = ev && ev.target && ev.target.closest ? ev.target.closest("[data-store-pick]") : null;
        if (!opt || opt.disabled) return;
        var want = opt.getAttribute("data-store-pick");
        var now = (app.profile && app.profile.storage_mode === "drive") ? "drive" : "platform";
        show("storageMsg", false);
        if (want === now) return;
        if (want === "platform") {
          return app.updateProfile({ storage_mode: "platform" }).then(renderDriveSwitch)
            .catch(function () { setMsg("storageMsg", t("genericError"), "error"); });
        }
        /* الربط من الخادم: موافقة واحدة تعطينا رمز تحديث دائم، فلا يطلب
           الاذن مرة اخرى ابدا. المتصفح ينتقل بنفسه لان التصفح لا يحمل الجلسة. */
        if (config.driveServer && app.driveServerConnect) {
          opt.disabled = true;
          return app.driveServerConnect().then(function (url) { window.location.href = url; })
            .catch(function () {
              opt.disabled = false; renderDriveSwitch();
              setMsg("storageMsg", t("storageDriveDenied"), "error");
            });
        }
        renderDriveSwitch();
        setMsg("storageMsg", t("storageDriveUnavailable"), "error");
        return Promise.resolve();
      }

      function currentPlan() {
        for (var i = 0; i < state.plans.length; i++) if (state.plans[i].code === state.planCode) return state.plans[i];
        return null;
      }

      function limitText(v) {
        if (v === null || v === undefined) return t("unlimited");
        return String(v);
      }

      /* اشتراك بنقرة واحدة: Google يقبل رابط ICS مباشرة، وآبل وأوتلوك عبر webcal. */
      function syncCalendarLinks(url) {
        if (!url) return;
        /* رابط الشاشة المكتبية من رمز التقويم نفسه: لا رمز جديد ولا صلاحية جديدة */
        var dev = el("deviceUrl");
        if (dev) dev.value = url.replace("/api/calendar/", "/api/device/").replace(/\.ics$/, "");
        /* باركود شاشة زاهي: /link?to=<عنوان محلي> يحول الى هنا مع link=<to>، وزر واحد يفتح
           http://<to>/dtoken?t=<الرمز> على شبكة الجهاز نفسها فيحفظه الجهاز ويرد «تم الربط»
           (امر المهندس رعد 2026-09-12). رابط يضغطه المستخدم لا fetch ولا تحويل تلقائي. */
        var linkBtn = el("deviceLinkBtn"), linkHint = el("deviceLinkHint");
        if (linkBtn) {
          var to = "";
          try { to = String(new URLSearchParams(window.location.search).get("link") || "").trim().toLowerCase(); } catch (e) { to = ""; }
          var tok = url.match(/\/api\/calendar\/([A-Za-z0-9_-]+)\.ics$/);
          var okTo = to.length <= 64 && /^(?:10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}|[a-z0-9-]+\.local)$/.test(to);
          var show = !!(okTo && tok);
          if (show) linkBtn.href = "http://" + to + "/dtoken?t=" + encodeURIComponent(tok[1]);
          linkBtn.hidden = !show;
          if (linkHint) linkHint.hidden = !show;
        }
        var g = el("googleCalBtn");
        var a = el("appleCalBtn");
        if (g) g.href = "https://calendar.google.com/calendar/r?cid=" + encodeURIComponent(url);
        if (a) a.href = url.replace(/^https?:/, "webcal:");
      }

      function renderSubscription() {
        var list = el("planSummary");
        if (!app.org) {
          list.innerHTML = '<li><span class="waitlist-msg error">' + esc(t("noOrg")) + "</span></li>";
          var form = el("upgradeForm");
          if (form) form.style.display = "none";
          return;
        }
        var plan = currentPlan();
        var code = lang();
        var name = plan ? (plan["name_" + code] || plan.name_en || plan.code) : state.planCode;
        var limits = (plan && plan.limits) || {};
        var expiresAt = (state.sub && state.sub.expires_at) || app.org.plan_expires_at || null;
        var channelNames = (Array.isArray(limits.channels) ? limits.channels : ["telegram"]).map(function (ch) {
          return t(CHANNEL_KEYS[ch] || ch);
        }).join("، ");
        list.innerHTML =
          "<li><span>" + esc(t("currentPlanLabel")) + "</span><span>" + esc(name) + "</span></li>" +
          "<li><span>" + esc(t("expiresLabel")) + "</span><span>" + esc(expiresAt ? fmtDate(expiresAt) : t("noExpiry")) + "</span></li>" +
          "<li><span>" + esc(t("limitMembers")) + "</span><span>" + esc(limitText(limits.members)) + "</span></li>" +
          "<li><span>" + esc(t("limitItems")) + "</span><span>" + esc(limitText(limits.items)) + "</span></li>" +
          "<li><span>" + esc(t("limitChannels")) + "</span><span>" + esc(channelNames) + "</span></li>" +
          "<li><span>" + esc(t("limitImports")) + "</span><span>" + esc(limitText(limits.imports_per_month)) + "</span></li>";
        renderUpgrade();
      }

      /* ---------- طلب الترقية داخل الموقع ---------- */

      /* الباقات المعروضة تأتي من الجدول لا من قائمة مكتوبة في الشيفرة:
         أي شريحة جديدة تضاف سطرا في plans فتظهر هنا بلا تعديل. */
      function upgradeCodes() {
        return (state.plans || [])
          .filter(function (p) { return p.active !== false && p.code !== "trial" && p.code !== "expired"; })
          .slice()
          .sort(function (a, b) { return (a.sort_order || 0) - (b.sort_order || 0); })
          .map(function (p) { return p.code; });
      }

      function planLabel(code) {
        var p = null;
        for (var i = 0; i < (state.plans || []).length; i++) if (state.plans[i].code === code) p = state.plans[i];
        if (!p) return code;
        return p["name_" + lang()] || p.name_en || p.code;
      }

      function renderUpgrade() {
        var sel = el("upgradePlan");
        if (!sel) return;
        var options = "";
        upgradeCodes().forEach(function (code) {
          if (code === state.planCode) return;
          options += '<option value="' + code + '">' + esc(planLabel(code)) + "</option>";
        });
        sel.innerHTML = options;
        fillUpgradePeriod();
        renderUpgradePrice();
        el("upgradeForm").style.display = options ? "" : "none";
      }



      /* السعر يقرأ من جدول الباقات لا من نص مكتوب، ويتبع المدة المختارة. */
      function planRow(code) {
        for (var i = 0; i < (state.plans || []).length; i++) if (state.plans[i].code === code) return state.plans[i];
        return null;
      }

      function renderUpgradePrice() {
        var box = el("upgradePrice"), sel = el("upgradePlan"), per = el("upgradePeriod");
        if (!box || !sel || !per) return;
        var row = planRow(sel.value);
        var amount = row ? (per.value === "yearly" ? row.price_yearly_sar : row.price_monthly_sar) : null;
        box.innerHTML = amount
          ? esc(app.fmtAmount(Number(amount))) + ' <span class="sar-symbol" aria-label="ريال سعودي"></span>'
          : "";
      }

      /* المدد المعروضة هي التي للباقة سعر فيها فعلا: باقة الشركات سنوية فقط،
         فلو عرضنا لها «شهري» لظهر سعر فارغ ولانشا طلب بلا مبلغ. */
      function fillUpgradePeriod() {
        var per = el("upgradePeriod"), sel = el("upgradePlan");
        if (!per) return;
        var row = sel ? planRow(sel.value) : null;
        var hasMonthly = !!(row && row.price_monthly_sar !== null && row.price_monthly_sar !== undefined);
        var hasYearly = !!(row && row.price_yearly_sar !== null && row.price_yearly_sar !== undefined);
        if (!row) { hasMonthly = true; hasYearly = true; }
        var html = (hasMonthly ? '<option value="monthly">' + esc(t("periodMonthly")) + "</option>" : "") +
                   (hasYearly ? '<option value="yearly">' + esc(t("periodYearly")) + "</option>" : "");
        if (per.innerHTML !== html) per.innerHTML = html;
        per.value = hasYearly ? "yearly" : "monthly";
        per.disabled = !(hasMonthly && hasYearly);
      }

      /* الدفع داخل النظام: ينشأ الطلب في الوركر ثم يحول صاحبه إلى البوابة،
         وعند نجاح التحصيل تفعل القاعدة الاشتراك وحدها بلا تدخل أحد. */
      function submitUpgrade() {
        var btn = el("upgradeBtn"), sel = el("upgradePlan"), per = el("upgradePeriod");
        if (!app.org) { setMsg("upgradeMsg", t("noOrg"), "error"); return; }
        btn.disabled = true;
        if (!config.payEnabled) {
          btn.disabled = false;
          setMsg("upgradeMsg", t("payNotReady"), "error");
          return;
        }
        setMsg("upgradeMsg", t("payOpening"));
        window.mrzahiAuth.getSession().then(function (session) {
          var jwt = session && session.access_token;
          if (!jwt) throw new Error("no session");
          return swFetch("/api/pay/paypal/create", {
            method: "POST",
            headers: { "Content-Type": "application/json", Authorization: "Bearer " + jwt },
            body: JSON.stringify({ org: app.org.id, plan: sel.value, period: per ? per.value : "yearly" }),
          }, 15000);
        }).then(function (res) { return res.json(); }).then(function (out) {
          if (!out || !out.url) throw new Error(out && out.error ? out.error : "no url");
          window.location.href = out.url;
        }).catch(function () {
          btn.disabled = false;
          setMsg("upgradeMsg", t("payFailed"), "error");
        });
      }

      /* ---------- sign out ---------- */

      function signOut() {
        var btn = el("signOutBtn");
        btn.disabled = true;
        btn.textContent = t("signingOut");
        var forget = function () { var f = window.mrzahiApp && window.mrzahiApp.forgetDevice; if (f) f(); };
        var go = function () { forget(); window.location.href = "/login.html"; };
        forget();
        window.mrzahiAuth.signOut().then(go).catch(go);
      }

      /* ---------- boot ---------- */

      function showUnavailable() {
        show("loadingCard", false);
        show("settingsMain", false);
        show("unavailableCard", true);
      }

      function rerender() {
        if (!state.loaded) return;
        renderChannels();
        renderRules();
        renderSubscription();
        var so = el("signOutBtn");
        if (so && !so.disabled) so.textContent = t("signOutBtn");
        applyEntityType();
        renderDriveSwitch();   /* «Google Drive غير متاح» بلغة الواجهة الجديدة */
        paintStorageValue();   /* «غير محدود» بلغة الواجهة الجديدة */
      }
      window.__settingsRerender = rerender;


      /* ---------- بطاقة المنشأة: بيانات تخدم كل القطاعات ---------- */
      var OP_FIELDS = { opLegalName: "legal_name", opCr: "cr_number", opVat: "vat_number", opUnified: "unified_number",
        opLicense: "license_number", opPhone: "phone", opEmail: "email", opWebsite: "website",
        opBank: "bank_name", opAccountNumber: "account_number", opIban: "iban", opAccountName: "account_name" };

