    /* مسيرات الرواتب (امر المهندس رعد 2026-10-01). الحساب كله في القاعدة (0175): الصفحة
       تقرأ الاسطر وترسل المدخلات اليدوية وحدها، ولا تحسب رقما مشتقا بنفسها. */
    (function () {
      "use strict";
      var app = null;
      var state = { runs: [], run: null, lines: [], settings: null, canApprove: false, accounts: null, editing: null };
      function $(id) { return document.getElementById(id); }
      function t(k) { if (app && app.t) return app.t(k); var d = translations[lang()] || translations.ar; return d[k] || translations.ar[k] || k; }
      function esc(v) { return app && app.escapeHtml ? app.escapeHtml(v) : String(v == null ? "" : v).replace(/[&<>"']/g, function (c) { return ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]; }); }
      function show(id, on) { var el = $(id); if (el) el.hidden = !on; }
      function num(v) { var n = Number(v); return isFinite(n) ? n : 0; }
      function amt(v) { return app && app.fmtAmount ? app.fmtAmount(num(v)) : num(v).toFixed(2); }
      function money(v) { return esc(amt(v)) + ' <span class="sar-symbol" aria-label="' + esc(t("riyal")) + '"></span>'; }
      function monthLabel(period) {
        var d = new Date(String(period).slice(0, 7) + "-01T00:00:00");
        try { return new Intl.DateTimeFormat(lang() === "ar" ? "ar-SA-u-nu-latn-ca-gregory" : lang(), { month: "long", year: "numeric" }).format(d); }
        catch (e) { return String(period).slice(0, 7); }
      }
      function client() { return app.client; }
      function rpc(name, args) {
        return client().rpc(name, args).then(function (r) { if (r.error) throw r.error; return r.data; });
      }
      function say(id, text) { var m = $(id); if (!m) return; m.textContent = text || ""; m.hidden = !text; }
      function errText(err) {
        var msg = String((err && (err.message || err.code)) || "");
        if (/PAYROLL_LOCKED/.test(msg)) return t("locked");
        if (/OWNER_ONLY/.test(msg)) return t("ownerOnly");
        if (/NOT_ALLOWED|42501/.test(msg)) return t("notAllowed");
        return (app && app.errorSay) ? app.errorSay(err, "genericError") : t("genericError");
      }
      function statusBadge(s) {
        var cls = s === "paid" ? "status-done" : s === "approved" ? "status-open" : "status-cancelled";
        return '<span class="' + cls + '">' + esc(t("st_" + s)) + "</span>";
      }

      /* ---------- القائمة ---------- */
      function loadRuns() {
        return client().from("payroll_runs").select("id,period,status,totals,acct_status,acct_error,approved_at,paid_at")
          .eq("org_id", app.org.id).order("period", { ascending: false }).limit(36)
          .then(function (r) { if (r.error) throw r.error; state.runs = r.data || []; renderRuns(); });
      }
      function renderRuns() {
        var body = $("runsBody");
        body.innerHTML = state.runs.map(function (r) {
          var tt = r.totals || {};
          return "<tr><td>" + esc(monthLabel(r.period)) + "</td><td class=\"cell-num\">" + esc(String(num(tt.employees))) + "</td>" +
            '<td class="cell-num">' + money(tt.gross) + '</td><td class="cell-num">' + money(tt.deductions) + "</td>" +
            '<td class="cell-num"><strong>' + money(tt.net) + "</strong></td><td>" + statusBadge(r.status) + "</td>" +
            "<td>" + esc(r.acct_status ? t("acct_" + r.acct_status) : t("acctNone")) + "</td>" +
            '<td><button type="button" class="chat-option-btn" data-open="' + esc(r.id) + '">' + esc(t("open")) + "</button></td></tr>";
        }).join("");
        show("runsWrap", state.runs.length > 0);
        show("runsEmpty", state.runs.length === 0);
      }

      /* ---------- المسير ---------- */
      function openRun(id) {
        return Promise.all([
          client().from("payroll_runs").select("*").eq("id", id).single(),
          client().from("payroll_lines").select("*").eq("run_id", id).order("employee_name")
        ]).then(function (res) {
          if (res[0].error) throw res[0].error;
          if (res[1].error) throw res[1].error;
          state.run = res[0].data; state.lines = res[1].data || [];
          renderRun();
          show("listCard", false); show("setCard", false); show("runCard", true);
        });
      }
      function renderRun() {
        var r = state.run; if (!r) return;
        var tt = r.totals || {};
        var draft = r.status === "draft", approved = r.status === "approved", paid = r.status === "paid";
        $("runTitle").textContent = t("runOf") + " " + monthLabel(r.period);
        $("runStatus").innerHTML = statusBadge(r.status);
        /* الكلام فوق الرقم كبقية بطاقات المنصة (امر المهندس رعد 2026-09-20) */
        $("runTotals").innerHTML = [
          ["tEmployees", esc(String(num(tt.employees)))], ["tGross", money(tt.gross)], ["tDeductions", money(tt.deductions)],
          ["tNet", money(tt.net)], ["tGosiEmployer", money(tt.gosi_employer)]
        ].map(function (x) {
          return '<div class="total-card"><span class="total-label">' + esc(t(x[0])) + '</span><span class="total-value">' + x[1] + "</span></div>";
        }).join("");
        var warns = [];
        if (num(tt.no_iban) > 0) warns.push(t("warnNoIban").replace("{n}", String(num(tt.no_iban))));
        if (num(tt.negative) > 0) warns.push(t("warnNegative").replace("{n}", String(num(tt.negative))));
        say("runWarn", warns.join(" "));

        $("linesBody").innerHTML = state.lines.map(function (l) {
          var add = num(l.overtime) + num(l.bonus);
          var absLate = num(l.absence_deduction) + num(l.late_deduction);
          var other = num(l.advance_deduction) + num(l.other_deduction);
          var days = l.days_override != null ? l.days_override : l.days_paid;
          var acts = '<button type="button" class="chat-option-btn" data-slip="' + esc(l.id) + '">' + esc(t("payslip")) + "</button>";
          if (draft) acts = '<button type="button" class="chat-option-btn" data-edit="' + esc(l.id) + '">' + esc(t("edit")) + "</button>" + acts;
          return "<tr" + (num(l.net) < 0 ? ' class="is-negative"' : "") + ">" +
            '<td><div class="cell-stack"><span class="item-title">' + esc(l.employee_name) + "</span>" +
              '<span class="item-cat">' + esc([l.employee_number, l.is_saudi ? "SA" : (l.nationality || "")].filter(Boolean).join(" · ")) + "</span></div></td>" +
            '<td class="cell-num">' + esc(String(num(days))) + "</td>" +
            '<td class="cell-num">' + money(l.earned) + "</td>" +
            '<td class="cell-num">' + (add ? money(add) : "-") + "</td>" +
            '<td class="cell-num">' + money(l.gosi_employee) + "</td>" +
            '<td class="cell-num">' + (absLate ? money(absLate) : "-") + "</td>" +
            '<td class="cell-num">' + (num(l.unpaid_leave_deduction) ? money(l.unpaid_leave_deduction) : "-") + "</td>" +
            '<td class="cell-num">' + (other ? money(other) : "-") + "</td>" +
            '<td class="cell-num"><strong>' + money(l.net) + "</strong></td>" +
            '<td><div class="chat-options row-actions">' + acts + "</div></td></tr>";
        }).join("");
        show("linesWrap", state.lines.length > 0);
        show("linesEmpty", state.lines.length === 0);

        show("refreshBtn", draft);
        show("approveBtn", draft && state.canApprove);
        show("reopenBtn", approved && state.canApprove);
        show("paidBtn", approved && state.canApprove);
        show("bankWrap", (approved || paid) && state.lines.length > 0);
        show("slipsBtn", state.lines.length > 0);
        show("runDanger", draft);
        var acct = "";
        if (paid && r.acct_status) {
          acct = t("acct_" + r.acct_status) + (r.acct_error ? " — " + r.acct_error : "");
        }
        say("acctLine", acct);
        show("acctRetry", paid && state.canApprove && (r.acct_status === "failed" || r.acct_status === "waiting"));
        say("runMsg", "");
      }
      function reloadRun() { return openRun(state.run.id).then(loadRuns); }

      function generate() {
        var m = $("monthPick").value;
        if (!/^\d{4}-\d{2}$/.test(m)) return;
        $("genBtn").disabled = true; say("listMsg", "");
        rpc("payroll_generate", { p_org: app.org.id, p_period: m + "-01" })
          .then(function (id) { return loadRuns().then(function () { return openRun(id); }); })
          .catch(function (e) { say("listMsg", errText(e)); })
          .finally(function () { $("genBtn").disabled = false; });
      }
      function setStatus(to, confirmKey) {
        var ask = confirmKey ? Promise.resolve(window.confirm(t(confirmKey))) : Promise.resolve(true);
        ask.then(function (ok) {
          if (!ok) return;
          return rpc("payroll_run_set_status", { p_run: state.run.id, p_status: to }).then(function (res) {
            if (res && res.status === "empty") { say("runMsg", t("emptyRun")); return; }
            if (res && res.status !== "ok") { say("runMsg", t("genericError")); return; }
            return reloadRun();
          });
        }).catch(function (e) { say("runMsg", errText(e)); });
      }

      /* ---------- تعديل السطر ---------- */
      var LINE_FIELDS = [["fOvertime", "overtime"], ["fBonus", "bonus"], ["fExtraAbsence", "extra_absence_days"],
                         ["fAdvance", "advance_deduction"], ["fOtherDed", "other_deduction"], ["fDaysOverride", "days_override"]];
      function editLine(id) {
        var l = state.lines.filter(function (x) { return x.id === id; })[0]; if (!l) return;
        state.editing = l;
        $("lineTitle").textContent = t("lineEditTitle") + " — " + l.employee_name;
        LINE_FIELDS.forEach(function (f) {
          var v = l[f[1]];
          $(f[0]).value = (f[1] === "days_override" ? (v == null ? "" : v) : (num(v) ? v : ""));
        });
        $("fIsSaudi").checked = !!l.is_saudi;
        $("fNote").value = l.note || "";
        say("lineMsg", "");
        show("lineCard", true);
        $("lineCard").scrollIntoView({ block: "nearest" });
      }
      function saveLine(e) {
        e.preventDefault();
        var l = state.editing; if (!l) return;
        var patch = { is_saudi: $("fIsSaudi").checked, note: $("fNote").value };
        LINE_FIELDS.forEach(function (f) { patch[f[1]] = String($(f[0]).value || "").trim(); });
        $("lineSave").disabled = true;
        rpc("payroll_line_update", { p_line: l.id, p_patch: patch }).then(function (res) {
          if (res && res.status === "bad_value") { say("lineMsg", t("badValue")); return; }
          show("lineCard", false);
          return reloadRun();
        }).catch(function (err) { say("lineMsg", errText(err)); })
          .finally(function () { $("lineSave").disabled = false; });
      }
      function removeLine() {
        var l = state.editing; if (!l) return;
        var ask = app.confirmDanger ? app.confirmDanger(l.employee_name) : Promise.resolve(window.confirm(t("removeLine")));
        ask.then(function (ok) {
          if (!ok) return;
          return rpc("payroll_line_remove", { p_line: l.id }).then(function () { show("lineCard", false); return reloadRun(); });
        }).catch(function (err) { say("lineMsg", errText(err)); });
      }

      /* ---------- ملف التحويل البنكي ---------- */
      function bankRows() {
        return state.lines.filter(function (l) { return String(l.iban || "").trim() && num(l.net) > 0; }).map(function (l) {
          var iban = String(l.iban).replace(/\s+/g, "").toUpperCase();
          return [l.employee_name, l.id_number || "", l.employee_number || "", iban.slice(4, 6), iban,
                  num(l.basic), num(l.housing), num(l.transport) + num(l.other_allowances), num(l.total_deductions), num(l.net)];
        });
      }
      function bankName(ext) { return "payroll-" + String(state.run.period).slice(0, 7) + "." + ext; }
      function download(blob, name) {
        var a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = name;
        document.body.appendChild(a); a.click(); setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 500);
      }
      function bankCsv() {
        var rows = [t("bankCols")].concat(bankRows());
        var csv = rows.map(function (r) { return r.map(function (c) { var s = String(c); return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; }).join(","); }).join("\r\n");
        download(new Blob(["﻿" + csv], { type: "text/csv;charset=utf-8" }), bankName("csv"));
        say("runMsg", t("bankNote"));
      }
      function bankXlsx() {
        if (!window.XLSX) { bankCsv(); return; }
        var ws = window.XLSX.utils.aoa_to_sheet([t("bankCols")].concat(bankRows()));
        var wb = window.XLSX.utils.book_new();
        window.XLSX.utils.book_append_sheet(wb, ws, String(state.run.period).slice(0, 7));
        window.XLSX.writeFile(wb, bankName("xlsx"));
        say("runMsg", t("bankNote"));
      }

      /* ---------- القسائم: صفحة طباعة بلا الوان، الحبر وحده ---------- */
      function slipHtml(l) {
        var row = function (k, v) { return num(v) ? "<tr><td>" + esc(t(k)) + "</td><td class=\"n\">" + esc(amt(v)) + "</td></tr>" : ""; };
        var earn = row("basic", num(l.basic) * (num(l.days_override != null ? l.days_override : l.days_paid) / 30)) +
          row("housing", num(l.housing) * (num(l.days_override != null ? l.days_override : l.days_paid) / 30)) +
          row("transport", num(l.transport) * (num(l.days_override != null ? l.days_override : l.days_paid) / 30)) +
          row("otherAllow", num(l.other_allowances) * (num(l.days_override != null ? l.days_override : l.days_paid) / 30)) +
          row("overtime", l.overtime) + row("bonus", l.bonus);
        var ded = row("gosi", l.gosi_employee) + row("absence", l.absence_deduction) + row("late", l.late_deduction) +
          row("unpaidLeave", l.unpaid_leave_deduction) + row("advance", l.advance_deduction) + row("otherDed", l.other_deduction);
        return '<section class="slip"><h1>' + esc(t("slipTitle")) + " — " + esc(monthLabel(state.run.period)) + "</h1>" +
          "<h2>" + esc(app.org.name || "") + "</h2>" +
          '<table class="meta"><tr><td>' + esc(t("colEmployee")) + "</td><td>" + esc(l.employee_name) + "</td></tr>" +
          (l.employee_number ? "<tr><td>" + esc(t("empNumber")) + "</td><td>" + esc(l.employee_number) + "</td></tr>" : "") +
          (l.id_number ? "<tr><td>" + esc(t("idNumber")) + "</td><td>" + esc(l.id_number) + "</td></tr>" : "") +
          (l.iban ? "<tr><td>" + esc(t("iban")) + '</td><td dir="ltr">' + esc(l.iban) + "</td></tr>" : "") +
          "<tr><td>" + esc(t("daysPaid")) + "</td><td>" + esc(String(num(l.days_override != null ? l.days_override : l.days_paid))) + "</td></tr></table>" +
          "<h3>" + esc(t("slipEarnings")) + '</h3><table class="lines">' + earn + '<tr class="sum"><td></td><td class="n">' + esc(amt(l.gross)) + "</td></tr></table>" +
          "<h3>" + esc(t("slipDeductions")) + '</h3><table class="lines">' + (ded || "<tr><td>-</td><td></td></tr>") + '<tr class="sum"><td></td><td class="n">' + esc(amt(l.total_deductions)) + "</td></tr></table>" +
          '<p class="net">' + esc(t("slipNet")) + ": <strong>" + esc(amt(l.net)) + "</strong> " + esc(t("riyal")) + "</p></section>";
      }
      function printSlips(lines) {
        var w = window.open("", "_blank");
        if (!w) return;
        var dir = document.documentElement.dir || "rtl";
        w.document.write('<!DOCTYPE html><html lang="' + esc(lang()) + '" dir="' + esc(dir) + '"><head><meta charset="utf-8"><title>' + esc(t("slipTitle")) + "</title>" +
          "<style>body{font-family:'IBM Plex Sans Arabic',system-ui,sans-serif;margin:24px}.slip{page-break-after:always;max-width:640px;margin:0 auto 32px}" +
          "h1{font-size:20px;margin:0 0 4px}h2{font-size:15px;font-weight:500;margin:0 0 16px}h3{font-size:14px;margin:16px 0 6px}" +
          "table{width:100%;border-collapse:collapse}td{padding:4px 6px;border-bottom:1px solid currentColor}.meta td:first-child{width:40%}" +
          ".n{text-align:end;font-variant-numeric:tabular-nums}.sum td{font-weight:700;border-bottom:2px solid currentColor}.net{font-size:16px;margin-top:16px}</style></head><body>" +
          lines.map(slipHtml).join("") + "<script>window.onload=function(){window.print();}<\/script></body></html>");
        w.document.close();
      }

      /* ---------- الاعداد ---------- */
      var SET_NUM = [["sGosiSaudiEmp", "gosi_saudi_employee_pct"], ["sGosiSaudiEr", "gosi_saudi_employer_pct"],
                     ["sGosiNonEmp", "gosi_nonsaudi_employee_pct"], ["sGosiNonEr", "gosi_nonsaudi_employer_pct"],
                     ["sGosiCap", "gosi_cap"], ["sHours", "work_hours_per_day"]];
      var ACCT_KEYS = [["aSalariesExpense", "salaries_expense"], ["aGosiExpense", "gosi_expense"], ["aGosiPayable", "gosi_payable"],
                       ["aSalariesPayable", "salaries_payable"], ["aAdvances", "advances"]];
      function loadSettings() {
        return rpc("payroll_settings_get", { p_org: app.org.id }).then(function (s) {
          state.settings = s || {}; state.canApprove = !!(s && s.can_approve);
        });
      }
      function acctPost(path, body) {
        var auth = window.mrzahiAuth;
        return Promise.resolve(auth && auth.getSession ? auth.getSession() : null).then(function (sess) {
          var headers = { "Content-Type": "application/json" };
          if (sess && sess.access_token) headers.Authorization = "Bearer " + sess.access_token;
          return fetch(path, { method: "POST", headers: headers, body: JSON.stringify(body || {}) });
        }).then(function (res) { return res.json().catch(function () { return {}; }).then(function (d) { return { ok: res.ok, data: d || {} }; }); });
      }
      function openSettings() {
        var s = state.settings || {};
        SET_NUM.forEach(function (f) { $(f[0]).value = s[f[1]] != null ? s[f[1]] : ""; });
        $("sIncludeHousing").checked = s.gosi_include_housing !== false;
        $("sDeductLate").checked = s.deduct_late !== false;
        $("sMolId").value = s.employer_mol_id || "";
        $("sEmployerIban").value = s.employer_iban || "";
        var editable = state.canApprove;
        $("setForm").querySelectorAll("input,select").forEach(function (el) { el.disabled = !editable; });
        show("setSave", editable);
        say("setMsg", editable ? "" : t("adminOnlySettings"));
        show("listCard", false); show("runCard", false); show("setCard", true);
        var acc = s.accounts || {};
        var fill = function (list) {
          ACCT_KEYS.forEach(function (k) {
            var sel = $(k[0]);
            sel.innerHTML = '<option value="">' + esc(t("choose")) + "</option>" + (list || []).map(function (a) {
              return '<option value="' + esc(a.id) + '"' + (String(acc[k[1]] || "") === String(a.id) ? " selected" : "") + ">" +
                esc((a.code ? a.code + " — " : "") + a.name) + "</option>";
            }).join("");
            sel.disabled = !editable;
          });
        };
        if (!editable) { show("acctBox", false); return; }
        acctPost("/api/accounting/lookups", { org: app.org.id }).then(function (r) {
          var list = r.ok && r.data.lookups ? (r.data.lookups.accounts || r.data.lookups.expense_accounts) : null;
          show("acctBox", true);
          if (!list) { say("acctNote", t("notConnected")); fill([]); show("acctSelects", false); return; }
          say("acctNote", t("sAccountsHint")); show("acctSelects", true); fill(list);
        }).catch(function () { show("acctBox", true); say("acctNote", t("notConnected")); show("acctSelects", false); });
      }
      function saveSettings(e) {
        e.preventDefault();
        var p = {};
        SET_NUM.forEach(function (f) { var v = String($(f[0]).value || "").trim(); if (v !== "") p[f[1]] = v; });
        p.gosi_include_housing = $("sIncludeHousing").checked;
        p.deduct_late = $("sDeductLate").checked;
        p.employer_mol_id = $("sMolId").value;
        p.employer_iban = $("sEmployerIban").value;
        if (!$("acctSelects").hidden) {
          var acc = {};
          ACCT_KEYS.forEach(function (k) { var v = $(k[0]).value; if (v) acc[k[1]] = Number(v); });
          p.accounts = acc;
        }
        $("setSave").disabled = true;
        rpc("payroll_settings_save", { p_org: app.org.id, p_settings: p }).then(function (res) {
          if (res && res.status === "bad_value") { say("setMsg", t("badValue")); return; }
          say("setMsg", t("saved"));
          return loadSettings();
        }).catch(function (err) { say("setMsg", errText(err)); })
          .finally(function () { $("setSave").disabled = false; });
      }

      function backToList() { show("runCard", false); show("setCard", false); show("lineCard", false); show("listCard", true); }

      function wire() {
        var now = new Date();
        $("monthPick").value = now.getFullYear() + "-" + String(now.getMonth() + 1).padStart(2, "0");
        $("genBtn").addEventListener("click", generate);
        $("setBtn").addEventListener("click", openSettings);
        $("runsBody").addEventListener("click", function (e) {
          var b = e.target.closest("[data-open]"); if (b) openRun(b.getAttribute("data-open")).catch(function (err) { say("listMsg", errText(err)); });
        });
        $("backBtn").addEventListener("click", backToList);
        $("setBack").addEventListener("click", backToList);
        $("refreshBtn").addEventListener("click", function () {
          rpc("payroll_generate", { p_org: app.org.id, p_period: state.run.period }).then(reloadRun).catch(function (e) { say("runMsg", errText(e)); });
        });
        $("approveBtn").addEventListener("click", function () { setStatus("approved", "approveConfirm"); });
        $("reopenBtn").addEventListener("click", function () { setStatus("draft"); });
        $("paidBtn").addEventListener("click", function () { setStatus("paid", "paidConfirm"); });
        $("bankXlsxBtn").addEventListener("click", bankXlsx);
        $("bankCsvBtn").addEventListener("click", bankCsv);
        $("slipsBtn").addEventListener("click", function () { printSlips(state.lines); });
        $("acctRetry").addEventListener("click", function () {
          rpc("payroll_acct_retry", { p_run: state.run.id }).then(reloadRun).catch(function (e) { say("runMsg", errText(e)); });
        });
        $("deleteRunBtn").addEventListener("click", function () {
          var ask = app.confirmDanger ? app.confirmDanger(monthLabel(state.run.period)) : Promise.resolve(window.confirm(t("deleteRun")));
          ask.then(function (ok) {
            if (!ok) return;
            return rpc("payroll_run_delete", { p_run: state.run.id }).then(function () { backToList(); return loadRuns(); });
          }).catch(function (e) { say("runMsg", errText(e)); });
        });
        $("linesBody").addEventListener("click", function (e) {
          var ed = e.target.closest("[data-edit]"); if (ed) { editLine(ed.getAttribute("data-edit")); return; }
          var sl = e.target.closest("[data-slip]");
          if (sl) { var id = sl.getAttribute("data-slip"); printSlips(state.lines.filter(function (x) { return x.id === id; })); }
        });
        $("lineForm").addEventListener("submit", saveLine);
        $("lineCancel").addEventListener("click", function () { show("lineCard", false); });
        $("lineRemove").addEventListener("click", removeLine);
        $("setForm").addEventListener("submit", saveSettings);
      }
      window.__payrollRefresh = function () { renderRuns(); if (state.run && !$("runCard").hidden) renderRun(); };
      function boot() {
        app = window.mrzahiApp;
        if (!app || !app.ready) { show("loadingCard", false); show("unavailableCard", true); return; }
        app.ready.then(function (res) {
          if (!res || res.unavailable || app.unavailable) { show("loadingCard", false); show("unavailableCard", true); return; }
          if (!app.org) { show("loadingCard", false); show("noOrgCard", true); return; }
          wire();
          var reveal = function () { show("loadingCard", false); show("view", true); };
          return loadSettings().then(loadRuns).then(reveal, function (e) {
            reveal();
            say("listMsg", errText(e));
            show("genBtn", false); show("setBtn", false);
          });
        }).catch(function () { show("loadingCard", false); show("unavailableCard", true); });
      }
      if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot); else boot();
    })();
