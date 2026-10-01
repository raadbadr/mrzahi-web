    /* الحضور والانصراف (امر المهندس رعد 2026-10-01). الحساب كله في القاعدة (0178): الصفحة
       تعرض ما تعيده attendance_days وترسل البصمة والاعداد. الموظف العادي يرى بطاقته وحدها،
       والموارد البشرية ترى اللوحة، والمالك والمشرف الاعداد والاجهزة. */
    (function () {
      "use strict";
      var app = null;
      var state = { me: null, hr: false, settings: null, canAdmin: false, tab: "today", today: [], month: [], monthClosed: false, staff: [] };
      function $(id) { return document.getElementById(id); }
      function t(k) { if (app && app.t) return app.t(k); var d = translations[lang()] || translations.ar; return d[k] || translations.ar[k] || k; }
      function tr(k) { var d = translations[lang()] || translations.ar; return d[k] || translations.ar[k]; }
      function esc(v) { return app && app.escapeHtml ? app.escapeHtml(v) : String(v == null ? "" : v).replace(/[&<>"']/g, function (c) { return ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]; }); }
      function show(id, on) { var el = $(id); if (el) el.hidden = !on; }
      function say(id, text) { var m = $(id); if (!m) return; m.textContent = text || ""; m.hidden = !text; }
      function rpc(name, args) { return app.client.rpc(name, args).then(function (r) { if (r.error) throw r.error; return r.data; }); }
      function errText(err) {
        var msg = String((err && (err.message || err.code)) || "");
        if (/NOT_ALLOWED|42501/.test(msg)) return t("notAllowed");
        return (app && app.errorSay) ? app.errorSay(err, "genericError") : t("genericError");
      }
      function tz() { return (state.settings && state.settings.timezone) || "Asia/Riyadh"; }
      function hm(iso) {
        if (!iso) return "-";
        try { return new Intl.DateTimeFormat("en-GB", { hour: "2-digit", minute: "2-digit", hour12: false, timeZone: tz() }).format(new Date(iso)); }
        catch (e) { return String(iso).slice(11, 16); }
      }
      function localDay(d) {
        try { return new Intl.DateTimeFormat("en-CA", { timeZone: tz(), year: "numeric", month: "2-digit", day: "2-digit" }).format(d || new Date()); }
        catch (e) { return (d || new Date()).toISOString().slice(0, 10); }
      }
      function dur(min) { min = Number(min) || 0; return min ? Math.floor(min / 60) + ":" + String(min % 60).padStart(2, "0") : "-"; }
      var STATUS_CLS = { present: "status-done", absent: "status-overdue", leave: "status-open", weekend: "status-cancelled", pending: "status-cancelled", untracked: "status-cancelled" };
      function statusHtml(s) { return '<span class="' + (STATUS_CLS[s] || "") + '">' + esc(t("s_" + s)) + "</span>"; }

      /* ---------- بطاقتي ---------- */
      function loadMe() {
        return rpc("attendance_my_status", { p_org: app.org.id }).then(function (s) { state.me = s || {}; state.hr = !!(s && s.hr); renderMe(); });
      }
      function renderMe() {
        var me = state.me || {};
        show("meCard", !!me.staff || !state.hr);
        if (!me.staff) { say("meNote", t("meNotStaff")); show("punchBtn", false); $("meList").innerHTML = ""; return; }
        var today = me.today || [];
        var next = today.length % 2 === 0 ? "punchIn" : "punchOut";
        $("punchBtn").textContent = t(next);
        show("punchBtn", me.app_enabled !== false);
        $("meHours").textContent = t("workHours") + ": " + String(me.work_start || "").slice(0, 5) + " – " + String(me.work_end || "").slice(0, 5);
        $("meList").innerHTML = today.length
          ? today.map(function (p) { return "<li>" + esc(hm(p.at)) + " — " + esc(t(p.direction === "out" ? "dirOut" : p.direction === "in" ? "dirIn" : "dirAuto")) + "</li>"; }).join("")
          : "<li>" + esc(t("meNone")) + "</li>";
        if (me.app_enabled === false) say("meNote", t("st_app_disabled"));
      }
      function punch() {
        var me = state.me || {};
        $("punchBtn").disabled = true; say("meMsg", "");
        var send = function (pos) {
          var c = pos && pos.coords;
          return rpc("attendance_punch_me", { p_org: app.org.id, p_lat: c ? Number(c.latitude.toFixed(6)) : null,
            p_lng: c ? Number(c.longitude.toFixed(6)) : null, p_accuracy: c ? Math.round(c.accuracy) : null });
        };
        var go = me.geofence && navigator.geolocation
          ? new Promise(function (ok) {
              say("meMsg", t("locating"));
              navigator.geolocation.getCurrentPosition(function (p) { ok(p); }, function () { ok(null); }, { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 });
            }).then(send)
          : send(null);
        go.then(function (r) {
          r = r || {};
          if (r.status === "ok") { say("meMsg", t(r.direction === "out" ? "st_ok_out" : "st_ok_in")); return loadMe().then(function () { if (state.hr) loadToday(); }); }
          if (r.status === "outside") { say("meMsg", t("st_outside").replace("{d}", r.distance_m).replace("{r}", r.radius_m)); return; }
          say("meMsg", t("st_" + r.status) || t("genericError"));
        }).catch(function (e) { say("meMsg", errText(e)); })
          .finally(function () { $("punchBtn").disabled = false; });
      }

      /* ---------- لوحة الموارد البشرية ---------- */
      function setTab(tab) {
        state.tab = tab;
        ["today", "month", "settings"].forEach(function (k) {
          show("pane_" + k, k === tab);
          var b = $("tab_" + k); if (b) b.classList.toggle("is-active", k === tab);
        });
        if (tab === "today") loadToday();
        if (tab === "month") loadMonth();
        if (tab === "settings") renderSettings();
      }
      function loadToday() {
        var d = localDay();
        return rpc("attendance_days", { p_org: app.org.id, p_from: d, p_to: d }).then(function (rows) {
          state.today = rows || [];
          var grace = Number((state.settings && state.settings.grace_minutes) || 0);
          $("todayBody").innerHTML = state.today.map(function (r) {
            var late = Number(r.late_minutes) || 0;
            return "<tr><td>" + esc(r.name) + "</td><td>" + statusHtml(r.status) + '</td><td class="cell-num">' + esc(hm(r.first_in)) +
              '</td><td class="cell-num">' + esc(hm(r.last_out)) + '</td><td class="cell-num">' +
              (late > grace ? '<span class="status-overdue">' + esc(late + " " + t("minutes")) + "</span>" : "-") +
              '</td><td class="cell-num">' + esc(dur(r.worked_minutes)) + "</td></tr>";
          }).join("");
          show("todayWrap", state.today.length > 0); show("todayEmpty", state.today.length === 0);
          state.staff = state.today.map(function (r) { return { id: r.staff_item_id, name: r.name }; });
          fillStaffSelect();
        }).catch(function (e) { say("todayMsg", errText(e)); });
      }
      function fillStaffSelect() {
        var sel = $("mStaff"); if (!sel) return;
        sel.innerHTML = '<option value="">' + esc(t("choose")) + "</option>" + state.staff.map(function (s) {
          return '<option value="' + esc(s.staff_item_id || s.id) + '">' + esc(s.name) + "</option>";
        }).join("");
      }
      function monthRange() {
        var m = $("monthPick").value; if (!/^\d{4}-\d{2}$/.test(m)) return null;
        var y = Number(m.slice(0, 4)), mo = Number(m.slice(5, 7));
        var last = new Date(Date.UTC(y, mo, 0)).getUTCDate();
        return { from: m + "-01", to: m + "-" + String(last).padStart(2, "0") };
      }
      function loadMonth() {
        var r = monthRange(); if (!r) return;
        say("monthMsg", "");
        return Promise.all([
          rpc("attendance_days", { p_org: app.org.id, p_from: r.from, p_to: r.to }),
          app.client.from("attendance_months").select("staff_item_id").eq("org_id", app.org.id).eq("month", r.from).limit(1)
        ]).then(function (res) {
          var rows = res[0] || [];
          state.monthClosed = !!(res[1].data && res[1].data.length);
          var grace = Number((state.settings && state.settings.grace_minutes) || 0);
          var by = {};
          rows.forEach(function (d) {
            var k = d.staff_item_id;
            if (!by[k]) by[k] = { name: d.name, present: 0, absent: 0, leave: 0, late: 0 };
            if (d.status === "present") { by[k].present++; if (d.late_minutes > grace) by[k].late += d.late_minutes; }
            if (d.status === "absent") by[k].absent++;
            if (d.status === "leave") by[k].leave++;
          });
          var list = Object.keys(by).map(function (k) { return by[k]; }).sort(function (a, b) { return a.name.localeCompare(b.name); });
          $("monthBody").innerHTML = list.map(function (x) {
            return "<tr><td>" + esc(x.name) + '</td><td class="cell-num">' + x.present + '</td><td class="cell-num">' +
              (x.absent ? '<span class="status-overdue">' + x.absent + "</span>" : "0") + '</td><td class="cell-num">' + x.leave +
              '</td><td class="cell-num">' + (x.late || 0) + "</td></tr>";
          }).join("");
          show("monthWrap", list.length > 0); show("monthEmpty", list.length === 0);
          say("monthState", t(state.monthClosed ? "closedBadge" : "openBadge"));
          show("closeBtn", !state.monthClosed && list.length > 0);
          show("reopenBtn", state.monthClosed);
        }).catch(function (e) { say("monthMsg", errText(e)); });
      }
      function closeMonth(reopen) {
        var r = monthRange(); if (!r) return;
        rpc(reopen ? "attendance_reopen_month" : "attendance_close_month", { p_org: app.org.id, p_month: r.from }).then(function (res) {
          res = res || {};
          if (res.status === "ok") { if (!reopen) say("monthMsg", t("r_closed").replace("{n}", res.employees)); return loadMonth(); }
          say("monthMsg", t("r_" + res.status) || t("genericError"));
        }).catch(function (e) { say("monthMsg", errText(e)); });
      }
      function manualPunch(e) {
        e.preventDefault();
        var at = $("mAt").value;
        if (!$("mStaff").value || !at) return;
        rpc("attendance_manual_punch", { p_org: app.org.id, p_staff: $("mStaff").value, p_at: new Date(at).toISOString(),
          p_direction: $("mDir").value, p_note: $("mNote").value }).then(function (res) {
          res = res || {};
          if (res.status === "ok") { $("mNote").value = ""; say("manualMsg", t("saved")); return loadToday(); }
          say("manualMsg", t("r_" + res.status) || t("genericError"));
        }).catch(function (err) { say("manualMsg", errText(err)); });
      }
      function checkUnlinked() {
        return rpc("attendance_relink", { p_org: app.org.id }).then(function (r) {
          var pins = (r && r.unlinked_pins) || [];
          if (r && r.linked) say("unlinkedMsg", t("r_linked").replace("{n}", r.linked));
          say("unlinkedNote", pins.length ? t("unlinkedTitle").replace("{pins}", pins.slice(0, 20).join("، ")) : "");
          show("relinkBtn", pins.length > 0);
        }).catch(function () { /* اللوحة تعمل بلا هذا التنبيه */ });
      }

      /* ---------- الاعداد والاجهزة ---------- */
      function loadSettings() {
        return rpc("attendance_settings_get", { p_org: app.org.id }).then(function (s) {
          state.settings = s || {}; state.canAdmin = !!(s && s.can_admin);
        });
      }
      function renderSettings() {
        var s = state.settings || {};
        $("sStart").value = String(s.work_start || "08:00").slice(0, 5);
        $("sEnd").value = String(s.work_end || "17:00").slice(0, 5);
        $("sGrace").value = s.grace_minutes != null ? s.grace_minutes : 15;
        $("sSince").value = s.tracking_since || "";
        $("sApp").checked = s.app_enabled !== false;
        $("sLat").value = s.geofence_lat != null ? s.geofence_lat : "";
        $("sLng").value = s.geofence_lng != null ? s.geofence_lng : "";
        $("sRadius").value = s.geofence_radius_m != null ? s.geofence_radius_m : "";
        var wk = s.weekend_days || [5, 6];
        var names = tr("days") || [];
        $("sWeekend").innerHTML = names.map(function (n, i) {
          return '<label class="check-field"><input type="checkbox" value="' + i + '"' + (wk.indexOf(i) !== -1 ? " checked" : "") + "><span>" + esc(n) + "</span></label>";
        }).join("");
        $("setForm").querySelectorAll("input,button").forEach(function (el) { el.disabled = !state.canAdmin; });
        $("devForm").querySelectorAll("input,button").forEach(function (el) { el.disabled = !state.canAdmin; });
        say("setMsg", state.canAdmin ? "" : t("adminOnly"));
        renderDevices();
      }
      function renderDevices() {
        var list = (state.settings && state.settings.devices) || [];
        $("devBody").innerHTML = list.map(function (d) {
          var seen = d.last_seen_at ? new Date(d.last_seen_at).toLocaleString(lang() === "ar" ? "ar-SA-u-nu-latn-ca-gregory" : lang(), { timeZone: tz() }) : t("devNever");
          var acts = state.canAdmin
            ? '<button type="button" class="chat-option-btn" data-dev="' + esc(d.id) + '" data-to="' + (d.status === "active" ? "disabled" : "active") + '">' +
                esc(t(d.status === "active" ? "devDisable" : "devEnable")) + "</button>" +
              '<button type="button" class="chat-option-btn is-danger" data-dev="' + esc(d.id) + '" data-to="delete">' + esc(t("devDelete")) + "</button>"
            : "";
          return '<tr><td dir="ltr">' + esc(d.serial) + "</td><td>" + esc(d.name || "-") + "</td><td>" +
            '<span class="' + (d.status === "active" ? "status-done" : "status-cancelled") + '">' + esc(t(d.status === "active" ? "devActive" : "devDisabled")) + "</span></td>" +
            "<td>" + esc(seen) + '</td><td class="cell-num">' + esc(String(d.punches_total || 0)) + '</td><td><div class="chat-options row-actions">' + acts + "</div></td></tr>";
        }).join("");
        show("devWrap", list.length > 0);
      }
      function saveSettings(e) {
        e.preventDefault();
        var wk = [];
        $("sWeekend").querySelectorAll("input:checked").forEach(function (c) { wk.push(Number(c.value)); });
        var p = { work_start: $("sStart").value, work_end: $("sEnd").value, grace_minutes: $("sGrace").value, weekend_days: wk,
                  tracking_since: $("sSince").value, app_enabled: $("sApp").checked,
                  geofence_lat: $("sLat").value, geofence_lng: $("sLng").value, geofence_radius_m: $("sRadius").value };
        rpc("attendance_settings_save", { p_org: app.org.id, p_settings: p }).then(function (r) {
          if (r && r.status === "ok") { say("setMsg", t("saved")); return loadSettings().then(renderSettings); }
          say("setMsg", t("badValue"));
        }).catch(function (err) { say("setMsg", errText(err)); });
      }
      function useMyLocation() {
        if (!navigator.geolocation) return;
        say("setMsg", t("locating"));
        navigator.geolocation.getCurrentPosition(function (p) {
          $("sLat").value = p.coords.latitude.toFixed(6); $("sLng").value = p.coords.longitude.toFixed(6);
          if (!$("sRadius").value) $("sRadius").value = 200;
          say("setMsg", "");
        }, function () { say("setMsg", t("st_need_location")); }, { enableHighAccuracy: true, timeout: 15000 });
      }
      function registerDevice(e) {
        e.preventDefault();
        rpc("attendance_device_register", { p_org: app.org.id, p_serial: $("dSerial").value, p_name: $("dName").value }).then(function (r) {
          r = r || {};
          if (r.status === "ok") { $("dSerial").value = ""; $("dName").value = ""; say("devMsg", t(r.seen_before ? "r_seen" : "r_registered")); return loadSettings().then(renderDevices); }
          say("devMsg", t("r_" + r.status) || t("genericError"));
        }).catch(function (err) { say("devMsg", errText(err)); });
      }
      function deviceAction(id, to) {
        var go = function () {
          return rpc("attendance_device_set", { p_device: id, p_status: to }).then(function () { return loadSettings().then(renderDevices); });
        };
        if (to !== "delete") { go().catch(function (e) { say("devMsg", errText(e)); }); return; }
        var ask = app.confirmDanger ? app.confirmDanger(t("devDelete")) : Promise.resolve(window.confirm(t("devDelete")));
        ask.then(function (ok) { if (ok) return go(); }).catch(function (e) { say("devMsg", errText(e)); });
      }

      function wire() {
        var now = new Date();
        $("monthPick").value = now.getFullYear() + "-" + String(now.getMonth() + 1).padStart(2, "0");
        $("punchBtn").addEventListener("click", punch);
        ["today", "month", "settings"].forEach(function (k) { $("tab_" + k).addEventListener("click", function () { setTab(k); }); });
        $("monthPick").addEventListener("change", loadMonth);
        $("closeBtn").addEventListener("click", function () { closeMonth(false); });
        $("reopenBtn").addEventListener("click", function () { closeMonth(true); });
        $("manualForm").addEventListener("submit", manualPunch);
        $("relinkBtn").addEventListener("click", checkUnlinked);
        $("setForm").addEventListener("submit", saveSettings);
        $("locBtn").addEventListener("click", useMyLocation);
        $("devForm").addEventListener("submit", registerDevice);
        $("devBody").addEventListener("click", function (e) {
          var b = e.target.closest("[data-dev]"); if (b) deviceAction(b.getAttribute("data-dev"), b.getAttribute("data-to"));
        });
      }
      window.__attendanceRefresh = function () {
        renderMe();
        if (state.hr) { if (state.tab === "settings") renderSettings(); else if (state.tab === "month") loadMonth(); else loadToday(); }
      };
      function boot() {
        app = window.mrzahiApp;
        if (!app || !app.ready) { show("loadingCard", false); show("unavailableCard", true); return; }
        app.ready.then(function (res) {
          if (!res || res.unavailable || app.unavailable) { show("loadingCard", false); show("unavailableCard", true); return; }
          if (!app.org) { show("loadingCard", false); show("noOrgCard", true); return; }
          wire();
          var reveal = function () { show("loadingCard", false); show("view", true); };
          return loadMe().then(function () {
            show("boardCard", state.hr);
            if (!state.hr) return;
            return loadSettings().then(function () {
              show("tab_settings", true);
              setTab("today");
              checkUnlinked();
            });
          }).then(reveal, function (e) { reveal(); say("meMsg", errText(e)); });
        }).catch(function () { show("loadingCard", false); show("unavailableCard", true); });
      }
      if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot); else boot();
    })();
