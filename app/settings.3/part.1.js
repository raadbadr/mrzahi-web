    /* ============================================================
     * Settings page logic — uses window.trackerApp (app/common.js)
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
        trackers: [],
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
        /* القنوات تأتي من حدود الباقة: التجريبية تيليغرام فقط، والمدفوعة تيليغرام والبريد. */
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
        var phone = String(el("profilePhone").value || "").trim().replace(/[\s-]/g, "");
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
        return app.linkTelegramByToken(token).then(function (res) {
          if (res && res.ok) { toast(t("tgLinked"), "success"); expanded.telegram = true; }
          else toast(t("tgLinkFailed"), "error");
          return reloadLinks();
        }).catch(function () { toast(t("tgLinkFailed"), "error"); });
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
        /* لا نعرض إلا القنوات التي تسمح بها الباقة (حاليا تيليغرام وحده). */
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
        return Promise.all([app.listTrackers(), app.listRules()]).then(function (res) {
          state.trackers = res[0] || [];
          state.rules = res[1] || [];
          renderRules();
        }).catch(function (err) {
          el("rulesWrap").innerHTML = '<p class="waitlist-msg error">' + esc(errorMessage(err)) + "</p>";
        });
      }

      /* Tracker-level rule (item_id null); rules come newest first so the first match wins. */
      function ruleForTracker(trackerId) {
        for (var i = 0; i < state.rules.length; i++) {
          var r = state.rules[i];
          if (r.tracker_id === trackerId && !r.item_id) return r;
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
        if (!state.trackers.length) { wrap.innerHTML = "<p>" + esc(t("noTrackers")) + "</p>"; return; }
        var allowed = allowedChannels();
        var html = '<div class="table-wrap"><table class="rules-table"><thead><tr>' +
          "<th>" + esc(t("colTracker")) + "</th>" +
          "<th>" + esc(t("colOffset")) + "</th>" +
          "<th>" + esc(t("colChannels")) + "</th>" +
          "<th>" + esc(t("colTarget")) + "</th>" +
          "<th>" + esc(t("colActions")) + "</th>" +
          "</tr></thead><tbody>";

        state.trackers.forEach(function (tracker) {
          var rule = ruleForTracker(tracker.id);
          var offset = rule ? Number(rule.offset_minutes) || 1440 : 1440;
          var channels = rule && Array.isArray(rule.channels) ? rule.channels : ["telegram"];
          var target = rule && rule.target === "all" ? "all" : "assignee";
          var offsets = OFFSETS.slice();
          if (offsets.indexOf(offset) === -1) offsets.push(offset);

          html += '<tr data-tracker="' + esc(tracker.id) + '"' + (rule ? ' data-rule="' + esc(rule.id) + '"' : "") + ">";
          html += '<td><span class="highlight">' + esc(tracker.name) + "</span>" +
                  (rule ? ' <span class="settings-note" style="color:var(--success)">' + esc(t("ruleActive")) + "</span>" : "") + "</td>";
          html += '<td><select class="waitlist-input rule-offset">';
          offsets.forEach(function (o) {
            html += '<option value="' + o + '"' + (o === offset ? " selected" : "") + ">" + esc(offsetLabel(o)) + "</option>";
          });
          html += "</select></td>";
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
          html += '<td><div class="chat-options">' +
                  '<button type="button" class="waitlist-btn" data-rule-action="save">' + esc(t("saveRuleBtn")) + "</button>" +
                  (rule ? '<button type="button" class="chat-option-btn" data-rule-action="delete">' + esc(t("deleteRuleBtn")) + "</button>" : "") +
                  "</div></td>";
          html += "</tr>";
        });

        html += "</tbody></table></div>";
        wrap.innerHTML = html;
      }

      function onRuleAction(ev) {
        var btn = ev.target.closest("[data-rule-action]");
        if (!btn) return;
        var row = btn.closest("tr[data-tracker]");
        if (!row) return;
        var action = btn.getAttribute("data-rule-action");
        var trackerId = row.getAttribute("data-tracker");
        var ruleId = row.getAttribute("data-rule") || null;
        var allowed = allowedChannels();

        if (action === "save") {
          var channels = [];
          row.querySelectorAll(".rule-channel").forEach(function (cb) {
            if (cb.checked && !cb.disabled && allowed.indexOf(cb.value) !== -1) channels.push(cb.value);
          });
          if (!channels.length) channels = ["telegram"];
          btn.disabled = true;
          app.saveRule({
            id: ruleId,
            tracker_id: trackerId,
            offset_minutes: Number(row.querySelector(".rule-offset").value) || 1440,
            channels: channels,
            target: row.querySelector(".rule-target").value
          }).then(function () {
            toast(t("ruleSaved"), "success");
            return loadRules();
          }).catch(function (err) { btn.disabled = false; toast(errorMessage(err), "error"); });
        } else if (action === "delete" && ruleId) {
          if (!window.confirm(t("deleteRuleConfirm"))) return;
          btn.disabled = true;
          app.deleteRule(ruleId).then(function () {
            toast(t("ruleDeleted"), "success");
            return loadRules();
          }).catch(function (err) { btn.disabled = false; toast(errorMessage(err), "error"); });
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

      function renderStorage() {
        var value = el("storageUsageValue");
        if (!value) return Promise.resolve();
        renderDriveSwitch();
        if (!app.org || typeof app.storageUsed !== "function") { value.textContent = "—"; return Promise.resolve(); }
        var capMb = state.limits ? state.limits.storage_mb : null;
        return app.storageUsed().then(function (used) {
          var usedMb = (Number(used) || 0) / 1048576;
          var capText = (capMb === null || capMb === undefined) ? t("unlimited") : fmtMb(Number(capMb));
          value.textContent = fmtMb(usedMb) + " / " + capText;
          var pct = capMb ? Math.min(100, Math.round(usedMb / Number(capMb) * 100)) : 0;
          var fill = el("storageBarFill");
          if (fill) fill.style.width = pct + "%";
          if (pct >= 90) setMsg("storageMsg", t("storageFull"), "error"); else show("storageMsg", false);
        }).catch(function () { value.textContent = "—"; });
      }

      function renderDriveSwitch() {
        var box = el("storageDriveToggle"), status = el("storageDriveStatus");
        if (!box || !status) return;
        var available = !!(app.driveOAuthAvailable && app.driveOAuthAvailable());
        var on = !!(app.profile && app.profile.storage_mode === "drive");
        box.checked = on && available;
        box.disabled = !available;
        status.textContent = !available ? t("storageDriveUnavailable") : (on ? t("storageDriveOn") : t("storageDriveOff"));
        var row = el("storageDriveRow");
        if (row) row.classList.toggle("is-on", box.checked);
        var link = el("storageDriveFolderLink");
        var f = on && app.driveFolderCached ? app.driveFolderCached() : null;
        if (link) { link.hidden = !f; if (f) { link.href = f.url; link.textContent = f.path; link.title = t("storageDriveFolder"); } }
      }

      /* التفويض يطلب بنقرة المستخدم نفسها، ولا يحفظ الخيار إلا بعد الإذن */
      function onDriveToggle() {
        var box = el("storageDriveToggle");
        show("storageMsg", false);
        if (!box.checked) {
          return app.updateProfile({ storage_mode: "platform" }).then(renderDriveSwitch)
            .catch(function () { box.checked = true; setMsg("storageMsg", t("genericError"), "error"); });
        }
        box.disabled = true;
        /* بالإذن نفسه ينشأ المجلد فورا في درايفه ليرى أين تذهب ملفاته */
        return app.connectDrive().then(function () { return app.updateProfile({ storage_mode: "drive" }); })
          .then(function () { return app.driveFolder ? app.driveFolder().catch(function () { return null; }) : null; })
          .then(function () { box.disabled = false; renderDriveSwitch(); })
          .catch(function () {
            box.checked = false; box.disabled = false; renderDriveSwitch();
            setMsg("storageMsg", t("storageDriveDenied"), "error");
          });
      }

      function currentPlan() {
        for (var i = 0; i < state.plans.length; i++) if (state.plans[i].code === state.planCode) return state.plans[i];
        return null;
      }

      function limitText(v) {
        if (v === null || v === undefined) return t("unlimited");
        return String(v);
      }

      /* اشتراك بنقرة واحدة: جوجل يقبل رابط ICS مباشرة، وآبل وأوتلوك عبر webcal. */
      function syncCalendarLinks(url) {
        if (!url) return;
        /* رابط الشاشة المكتبية من رمز التقويم نفسه: لا رمز جديد ولا صلاحية جديدة */
        var dev = el("deviceUrl");
        if (dev) dev.value = url.replace("/api/calendar/", "/api/device/").replace(/\.ics$/, "");
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
         أي شريحة جديدة تُضاف سطرا في plans فتظهر هنا بلا تعديل. */
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



      /* السعر يُقرأ من جدول الباقات لا من نص مكتوب، ويتبع المدة المختارة. */
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

      function fillUpgradePeriod() {
        var per = el("upgradePeriod");
        if (!per || per.options.length) return;
        per.innerHTML = '<option value="monthly">' + esc(t("periodMonthly")) + "</option>" +
                        '<option value="yearly">' + esc(t("periodYearly")) + "</option>";
        per.value = "yearly";
      }

      /* الدفع داخل النظام: يُنشأ الطلب في الوركر ثم يُحوَّل صاحبه إلى البوابة،
         وعند نجاح التحصيل تفعّل القاعدة الاشتراك وحدها بلا تدخل أحد. */
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
        window.trackerAuth.getSession().then(function (session) {
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
        var go = function () { window.location.href = "/login.html"; };
        try { localStorage.removeItem("tracker_org"); } catch (e) { /* ignore */ }
        window.trackerAuth.signOut().then(go).catch(go);
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
      }
      window.__settingsRerender = rerender;


      /* ---------- بطاقة المنشأة: بيانات تخدم كل القطاعات ---------- */
      var OP_FIELDS = { opLegalName: "legal_name", opCr: "cr_number", opVat: "vat_number", opUnified: "unified_number",
        opLicense: "license_number", opPhone: "phone", opEmail: "email", opWebsite: "website",
        opBank: "bank_name", opIban: "iban", opAccountName: "account_name" };

