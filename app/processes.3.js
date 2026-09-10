    (function () {
      "use strict";
      var app = null;
      /* مجالات المكتبة تتبع واجهة الحساب. المحاماة لا تعلن شيئا في حزمتها، فتبقى مجالاتها الست كما هي حرفا بحرف. */
      var LEGAL_AREAS = ["lawsuits","violations","contracts","licenses","documents","other"];
      var AREAS = LEGAL_AREAS.slice();
      var areaNames = null;   /* تسميات الحزمة إن أعلنتها */
      function loadAreas() {
        var cfg = app && app.packCfg ? app.packCfg("processes") : null;
        if (!Array.isArray(cfg) || !cfg.length) { AREAS = LEGAL_AREAS.slice(); areaNames = null; return; }
        AREAS = cfg.map(function (a) { return a.key; }).filter(Boolean);
        areaNames = {};
        cfg.forEach(function (a) { if (a && a.key) areaNames[a.key] = a.names || null; });
      }
      /* اسم المجال: من الحزمة بلغة الواجهة، وإلا من ترجمات الصفحة، وإلا المفتاح نفسه */
      function areaLabel(key) {
        var row = areaNames && areaNames[key];
        if (row) return row[(app && app.lang ? app.lang() : "ar")] || row.ar || key;
        var s = t("area_" + key);
        return s === "area_" + key ? key : s;
      }
      /* «طلبت تعديلات» حالة قائمة في القاعدة وتستعملها الشيفرة؛ غيابها من هذه
         القائمة كان يجعل القائمة تقع على «مسودة» عند فتح إجراء طلب تعديله،
         فيمحى طلب المراجع صامتا مع أول حفظ. */
      var STATUSES = ["draft","review","changes","published","archived"];
      var WIZ = ["wizBasics", "wizContext", "wizSteps", "wizReview"];
      var state = { list: [], members: [], names: {}, draft: null, area: "", search: "",
                    libView: "grid", wizStep: 0, current: null, statusFilter: "", zoom: 1 };
      function isAdmin() {
        var org = app && app.org;
        if (!org || !app.user) return false;
        return org.owner_id === app.user.id || org.role === "owner" || org.role === "admin";
      }
      function statusLabel(st) { return t("status_" + (st || "draft")); }
      function fmtWhen(iso) { return iso && app && app.fmtDate ? app.fmtDate(iso) : ""; }
      function $(id) { return document.getElementById(id); }
      function t(k) { if (app && app.t) return app.t(k); var d = translations[lang()] || translations.ar; return d[k] || translations.ar[k] || k; }
      function esc(v) { return app && app.escapeHtml ? app.escapeHtml(v) : String(v == null ? "" : v).replace(/[&<>"']/g, function (c) { return ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]; }); }
      function show(id, on) { var el = $(id); if (el) el.hidden = !on; }
      function name(uid) { return uid ? (state.names[uid] || "-") : "-"; }
      function memberOptions(sel, allowEmpty) {
        var html = allowEmpty ? '<option value="">' + esc(t("none")) + "</option>" : "";
        state.members.forEach(function (m) { html += '<option value="' + esc(m.user_id) + '"' + (sel === m.user_id ? " selected" : "") + ">" + esc(state.names[m.user_id] || "") + "</option>"; });
        return html;
      }
      /* حرفان من الاسم يكفيان للتعرف على الشخص في دائرة صغيرة */
      function rolePicker(stepIndex, role, current) {
        var list = state.members || [];
        if (!list.length) return '<span class="role-empty">' + esc(t("noMembersYet")) + "</span>";
        return list.map(function (m) {
          var full = state.names[m.user_id] || "";
          var on = current === m.user_id;
          return '<button type="button" class="name-pill' + (on ? " is-on" : "") + '" data-avatar="1"' +
                 ' data-i="' + stepIndex + '" data-role="' + role + '" data-member="' + esc(m.user_id) + '"' +
                 ' aria-pressed="' + (on ? "true" : "false") + '">' + esc(full) + "</button>";
        }).join("");
      }

      function newStep() { return { id: "s_" + Math.random().toString(36).slice(2, 7), type: "task", title: "", role: "", R: "", A: "", C: "", I: "", note: "", yesTarget: "", noTarget: "" }; }

      /* ---------- المكتبة: أرقامها، شرائحها، بطاقاتها أو جدولها ---------- */
      function visible() {
        var q = state.search.toLowerCase();
        var me = app && app.user ? app.user.id : "";
        return state.list.filter(function (p) {
          if (state.statusFilter === "published" && p.status !== "published") return false;
          if (state.statusFilter === "review" && p.status !== "review") return false;
          if (state.statusFilter === "mine" && !((p.status === "draft" || p.status === "changes") && p.created_by === me)) return false;
          if (state.area && p.area !== state.area) return false;
          if (!q) return true;
          var hay = ((p.name || "") + " " + (p.code || "") + " " + (p.description || "")).toLowerCase();
          return hay.indexOf(q) !== -1;
        });
      }

      function renderStats() {
        var all = state.list;
        var pub = all.filter(function (p) { return p.status === "published"; });
        var drafts = all.filter(function (p) { return p.status === "draft" || p.status === "changes"; });
        var review = all.filter(function (p) { return p.status === "review"; });
        var areas = {};
        pub.forEach(function (p) { if (p.area) areas[p.area] = true; });
        var boxes = [
          { key: "libPublished", n: pub.length, cls: "status-done" },
          { key: "libDrafts", n: drafts.length, cls: "status-open" },
          { key: "libReview", n: review.length, cls: "" },
          { key: "libAreas", n: Object.keys(areas).length, cls: "" }
        ];
        var html = boxes.map(function (b) {
          return '<div class="platform-stat-card"><span class="platform-stat-label">' + esc(t(b.key)) + "</span>" +
                 '<span class="platform-stat-value ' + b.cls + '">' + b.n + "</span></div>";
        }).join("");
        if (app && app.paint) app.paint($("libStats"), html); else $("libStats").innerHTML = html;
      }

      function renderPills() {
        var present = {};
        state.list.forEach(function (p) { if (p.area) present[p.area] = true; });
        var html = '<button type="button" class="pill' + (state.area ? "" : " is-on") + '" data-area="">' + esc(t("allAreas")) + "</button>" +
          AREAS.filter(function (a) { return present[a]; }).map(function (a) {
            return '<button type="button" class="pill' + (state.area === a ? " is-on" : "") + '" data-area="' + a + '">' + esc(areaLabel(a)) + "</button>";
          }).join("");
        if (app && app.paint) app.paint($("areaPills"), html); else $("areaPills").innerHTML = html;
      }

      function renderStatusPills() {
        var opts = [["", "allStatuses"], ["published", "libPublished"], ["review", "libReview"], ["mine", "myDrafts"]];
        var html = opts.map(function (o) {
          return '<button type="button" class="pill' + (state.statusFilter === o[0] ? " is-on" : "") + '" data-status="' + o[0] + '">' + esc(t(o[1])) + "</button>";
        }).join("");
        if (app && app.paint) app.paint($("statusPills"), html); else $("statusPills").innerHTML = html;
      }

      function pcard(p) {
        return '<button type="button" class="pcard" data-open="' + esc(p.id) + '">' +
          '<span class="proc-code">' + esc(p.code || t("status_draft")) + "</span>" +
          '<span class="pcard-name" data-tr>' + esc(p.name) + "</span>" +
          '<span class="pcard-desc" data-tr>' + esc(p.description || "") + "</span>" +
          '<span class="pcard-foot">' +
            '<span class="proc-status ' + esc(p.status) + '">' + esc(statusLabel(p.status)) + "</span>" +
            (p.area ? '<span class="area-tag">' + esc(t("area_" + p.area)) + "</span>" : "") +
            '<span class="pcard-steps">' + ((p.steps || []).length) + " " + esc(t("stepsCount")) + "</span>" +
          "</span></button>";
      }

      function renderList() {
        renderStats();
        renderStatusPills();
        renderPills();
        var rows = visible();
        var grid = state.libView !== "list";
        $("viewGrid").classList.toggle("is-on", grid);
        $("viewList").classList.toggle("is-on", !grid);
        show("libGrid", grid && rows.length > 0);
        show("listWrap", !grid && rows.length > 0);
        show("listEmpty", rows.length === 0);
        if (!rows.length) { $("listEmpty").textContent = state.list.length ? t("noProcesses") : t("libEmpty"); return; }
        if (grid) {
          var cards = rows.map(pcard).join("");
          if (app && app.paint) app.paint($("libGrid"), cards); else $("libGrid").innerHTML = cards;
          if (app && app.translateNodes) app.translateNodes($("libGrid"));
          return;
        }
        var body = $("listBody"); body.innerHTML = "";
        var admin = isAdmin();
        rows.forEach(function (p) {
          var on = p.active !== false;
          var tr = document.createElement("tr");
          tr.innerHTML =
            '<td><a href="#" class="cell-stack" data-open="' + esc(p.id) + '">' +
              '<span class="proc-code">' + esc(p.code || "—") + "</span>" +
              '<span class="item-title" data-tr>' + esc(p.name) + "</span></a></td>" +
            "<td>" + esc(name(p.published_by || p.created_by)) + "</td>" +
            "<td>" + esc(fmtWhen(p.updated_at)) + "</td>" +
            '<td><span class="proc-status ' + esc(p.status) + '">' + esc(statusLabel(p.status)) + "</span></td>" +
            '<td><div class="chat-options row-actions">' +
              (admin && p.status === "published"
                ? '<button type="button" class="chat-option-btn" data-toggle="' + esc(p.id) + '">' + esc(t(on ? "setInactive" : "setActive")) + "</button>"
                : "") +
              '<button type="button" class="chat-option-btn" data-edit="' + esc(p.id) + '">' + esc(t("edit")) + "</button>" +
            "</div></td>";
          body.appendChild(tr);
        });
        if (app && app.translateNodes) app.translateNodes(body);
      }

      /* ---------- المحرر ---------- */
      function openEditor(p) {
        state.draft = p ? JSON.parse(JSON.stringify(p)) : { name: "", area: AREAS[0] || "other", steps: [newStep()], status: "draft" };
        if (!Array.isArray(state.draft.steps) || !state.draft.steps.length) state.draft.steps = [newStep()];
        $("editorTitle").textContent = p ? t("editorEdit") + " — " + (p.code || "") : t("editorNew");
        $("fName").value = state.draft.name || "";
        $("fArea").innerHTML = AREAS.map(function (a) { return '<option value="' + a + '"' + (state.draft.area === a ? " selected" : "") + ">" + esc(areaLabel(a)) + "</option>"; }).join("");
        $("fOwner").innerHTML = memberOptions(state.draft.owner_id, true);
        $("fStatus").innerHTML = STATUSES.map(function (s) { return '<option value="' + s + '"' + (state.draft.status === s ? " selected" : "") + ">" + esc(t("status_" + s)) + "</option>"; }).join("");
        $("fFrequency").value = state.draft.frequency || ""; $("fTrigger").value = state.draft.trigger_text || "";
        $("fInputs").value = state.draft.inputs || ""; $("fOutputs").value = state.draft.outputs || ""; $("fDescription").value = state.draft.description || "";
        $("fCode").value = state.draft.code || "";
        show("deleteBtn", !!p);
        renderSteps();
        state.wizStep = 0;
        renderWizard();
        show("listCard", false); show("detailCard", false); show("editorCard", true);
        window.scrollTo({ top: 0, behavior: "smooth" });
      }

      /* المعالج: أساسيات ← سياق ← خطوات ← مراجعة، كما في المرجع */
      function renderWizard() {
        var steps = WIZ.map(function (k, i) {
          return '<span class="wiz-step' + (i === state.wizStep ? " is-on" : "") + (i < state.wizStep ? " is-done" : "") + '">' +
                 '<span class="n">' + (i < state.wizStep ? "✓" : (i + 1)) + "</span>" +
                 '<span class="t">' + esc(t(k)) + "</span></span>";
        }).join("");
        if (app && app.paint) app.paint($("wizSteps"), steps); else $("wizSteps").innerHTML = steps;
        Array.prototype.forEach.call(document.querySelectorAll(".wiz-pane"), function (pane) {
          pane.hidden = Number(pane.getAttribute("data-pane")) !== state.wizStep;
        });
        show("wizBack", state.wizStep > 0);
        show("wizNext", state.wizStep < WIZ.length - 1);
        show("saveBtn", state.wizStep === WIZ.length - 1);
        if (state.wizStep === WIZ.length - 1) renderWizReview();
      }

      function renderWizReview() {
        var d = readForm();
        var rows = [
          [t("fName"), d.name], [t("fCode"), d.code || "—"], [t("areaLabel"), t("area_" + (d.area || "other"))],
          [t("ownerLabel"), name(d.owner_id)], [t("freqLabel"), d.frequency || "—"],
          [t("fTrigger"), d.trigger_text || "—"], [t("fStatus"), statusLabel(d.status)],
          [t("stepsCount"), String((d.steps || []).length)]
        ];
        var html = '<div class="detail-meta">' + rows.map(function (r) {
          return '<div class="m"><div class="mk">' + esc(r[0]) + '</div><div class="mv">' + esc(r[1] || "—") + "</div></div>";
        }).join("") + "</div>" + flowHtml(d) + raciHtml(d).table;
        if (app && app.paint) app.paint($("wizReview"), html); else $("wizReview").innerHTML = html;
        if (app && app.translateNodes) app.translateNodes($("wizReview"));
      }
      function renderSteps() {
        var box = $("steps"); box.innerHTML = "";
        state.draft.steps.forEach(function (st, i) {
          var row = document.createElement("div"); row.className = "step-row";
          var targets = state.draft.steps.map(function (_, j) { return '<option value="' + (j + 1) + '">' + (j + 1) + "</option>"; }).join("");
          row.innerHTML =
            '<span class="snum">' + (i + 1) + "</span>" +
            '<div class="step-tools">' +
              '<button type="button" class="st-tool" data-up="' + i + '" title="' + esc(t("moveUp")) + '">↑</button>' +
              '<button type="button" class="st-tool" data-down="' + i + '" title="' + esc(t("moveDown")) + '">↓</button>' +
              '<button type="button" class="st-tool is-danger" data-del="' + i + '" title="' + esc(t("delete")) + '" aria-label="' + esc(t("delete")) + '">' +
                '<svg viewBox="0 0 24 24" aria-hidden="true" style="width:15px;height:15px;fill:currentColor"><path d="M6 19a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg></button></div>' +
            '<div class="sgrid">' +
              '<label><span class="mini-label">' + esc(t("stepType")) + '</span><select class="waitlist-input" data-f="type" data-i="' + i + '">' +
                '<option value="task"' + (st.type !== "decision" ? " selected" : "") + ">" + esc(t("typeTask")) + "</option>" +
                '<option value="decision"' + (st.type === "decision" ? " selected" : "") + ">" + esc(t("typeDecision")) + "</option></select></label>" +
              '<label><span class="mini-label">' + esc(t("stepTitle")) + '</span><input type="text" class="waitlist-input" data-f="title" data-i="' + i + '" value="' + esc(st.title) + '" maxlength="200" dir="auto"></label>' +
            "</div>" +
            '<div class="raci-grid">' +
              ["R","A","C","I"].map(function (k) {
                return '<div class="role-pick"><span class="mini-label">' + esc(t("raci_" + k)) + " (" + k + ")</span>" +
                       '<div class="avatars">' + rolePicker(i, k, st[k] || "") + "</div></div>";
              }).join("") +
            "</div>" +
            (st.type === "decision"
              ? '<div class="raci-grid" style="grid-template-columns:repeat(2,minmax(0,1fr))"><label><span class="mini-label">' + esc(t("yesTo")) + '</span><select class="waitlist-input" data-f="yesTarget" data-i="' + i + '"><option value="">-</option>' + targets + '</select></label>' +
                '<label><span class="mini-label">' + esc(t("noTo")) + '</span><select class="waitlist-input" data-f="noTarget" data-i="' + i + '"><option value="">-</option>' + targets + "</select></label></div>"
              : "") +
            '<label style="display:block;margin-top:.5rem"><span class="mini-label">' + esc(t("stepNote")) + '</span><input type="text" class="waitlist-input" data-f="note" data-i="' + i + '" value="' + esc(st.note || "") + '" maxlength="300" dir="auto"></label>';
          box.appendChild(row);
          if (st.type === "decision") { row.querySelector('[data-f="yesTarget"]').value = st.yesTarget || ""; row.querySelector('[data-f="noTarget"]').value = st.noTarget || ""; }
        });
      }
      function readForm() {
        var d = state.draft;
        d.name = $("fName").value.trim(); d.code = $("fCode").value.trim(); d.area = $("fArea").value;
        d.owner_id = $("fOwner").value || null; d.status = $("fStatus").value;
        d.frequency = $("fFrequency").value.trim(); d.trigger_text = $("fTrigger").value.trim(); d.inputs = $("fInputs").value.trim(); d.outputs = $("fOutputs").value.trim(); d.description = $("fDescription").value.trim();
        return d;
      }

      /* ---------- صفحة الإجراء ---------- */
      function flowHtml(p) {
        var steps = p.steps || [];
        if (!steps.length) return '<div class="flow"><p class="empty-note">' + esc(t("noSteps")) + "</p></div>";
        var html = "";
        steps.forEach(function (s2, i) {
          var who = ["R", "A"].map(function (k) { return s2[k] ? t("raci_" + k) + ": " + name(s2[k]) : ""; }).filter(Boolean).join(" · ");
          html += '<div class="flow-node ' + (s2.type === "decision" ? "decision" : "") + '">' +
                    "<strong>" + (i + 1) + '. <span data-tr>' + esc(s2.title || "") + "</span></strong>" +
                    (who ? '<span class="role">' + esc(who) + "</span>" : "") +
                    (s2.type === "decision"
                      ? '<span class="role flow-branch">' + esc(t("yes")) + " → " + esc(s2.yesTarget || "—") +
                        " · " + esc(t("no")) + " → " + esc(s2.noTarget || "—") + "</span>"
                      : "") +
                  "</div>";
          if (i < steps.length - 1) html += '<div class="flow-arrow"></div>';
        });
        return '<div class="flow">' + html + "</div>";
      }

      /* المصفوفة بشكل المرجع: رقم الخطوة ثم اسمها ثم أربعة أعمدة R A C I */
      function raciHtml(p) {
        var steps = p.steps || [];
        var rows = steps.map(function (s2, i) {
          return "<tr><td>" + (i + 1) + "</td>" +
                 '<td class="step-name" data-tr>' + esc(s2.title || "") + "</td>" +
                 ["R", "A", "C", "I"].map(function (k) {
                   return '<td class="rc">' + (s2[k] ? '<span class="raci-badge raci-' + k + '" title="' + esc(name(s2[k])) + '">' + k + "</span>" : "") + "</td>";
                 }).join("") + "</tr>";
        }).join("");
        var people = {};
        steps.forEach(function (s2) { ["R", "A", "C", "I"].forEach(function (k) { if (s2[k]) { people[s2[k]] = people[s2[k]] || {}; people[s2[k]][k] = true; } }); });
        var legend = Object.keys(people).map(function (uid) {
          return '<span class="li"><b>' + esc(name(uid)) + "</b>: " + Object.keys(people[uid]).join(" · ") + "</span>";
        }).join("");
        return {
          table: '<table class="items-table raci-table"><thead><tr><th>#</th><th>' + esc(t("stepTitle")) + "</th>" +
                 ["R", "A", "C", "I"].map(function (k) { return '<th class="rc" title="' + esc(t("raci_" + k)) + '">' + k + "</th>"; }).join("") +
                 "</tr></thead><tbody>" + (rows || "") + "</tbody></table>",
          legend: legend
        };
      }

      function detailActions(p) {
        var admin = isAdmin();
        var out = [];
        if (admin && p.status === "review") {
          out.push('<button type="button" class="waitlist-btn" data-act="publish">' + esc(t("approvePublish")) + "</button>");
          out.push('<button type="button" class="chat-option-btn" data-act="changes">' + esc(t("requestChanges")) + "</button>");
          out.push('<button type="button" class="chat-option-btn is-danger" data-act="reject">' + esc(t("rejectProc")) + "</button>");
        } else if (admin && p.status === "published") {
          out.push('<button type="button" class="chat-option-btn" data-act="unpublish">' + esc(t("unpublish")) + "</button>");
          out.push('<button type="button" class="chat-option-btn" data-act="edit">' + esc(t("edit")) + "</button>");
        } else if (p.status === "draft" || p.status === "changes") {
          out.push('<button type="button" class="waitlist-btn" data-act="review">' + esc(t("sendToReview")) + "</button>");
          out.push('<button type="button" class="chat-option-btn" data-act="edit">' + esc(t("continueEditing")) + "</button>");
        } else {
          out.push('<button type="button" class="chat-option-btn" data-act="edit">' + esc(t("edit")) + "</button>");
        }
        out.push('<button type="button" class="chat-option-btn" data-act="back">' + esc(t("back")) + "</button>");
        return out.join("");
      }

      function openDetail(p) {
        state.current = p;
        $("detailCode").textContent = p.code || "";
        $("detailTitle").textContent = p.name || "";
        $("detailDesc").textContent = p.description || "";
        $("detailStatus").textContent = statusLabel(p.status);
        $("detailStatus").className = "proc-status " + (p.status || "draft");

        var meta = [
          [t("areaLabel"), t("area_" + (p.area || "other"))],
          [t("ownerLabel"), name(p.owner_id)],
          [t("freqLabel"), p.frequency || "—"],
          [t("stepsCount"), String((p.steps || []).length)],
          [t("authorLabel"), name(p.created_by)]
        ];
        $("detailMeta").innerHTML = meta.map(function (m) {
          return '<div class="m"><div class="mk">' + esc(m[0]) + '</div><div class="mv">' + esc(m[1]) + "</div></div>";
        }).join("");

        var inputs = String(p.inputs || "").split("\n").filter(function (x) { return x.trim(); });
        var outputs = String(p.outputs || "").split("\n").filter(function (x) { return x.trim(); });
        var hasContext = !!(p.trigger_text || inputs.length || outputs.length);
        show("contextPanel", hasContext);
        if (hasContext) {
          $("contextBody").innerHTML =
            (p.trigger_text ? '<div class="ctx-block"><div class="mk">' + esc(t("fTrigger")) + '</div><div class="mv" data-tr>' + esc(p.trigger_text) + "</div></div>" : "") +
            '<div class="ctx-grid">' +
              (inputs.length ? '<div><div class="mk">' + esc(t("inputsTitle")) + "</div><ul class=\"ctx-list\">" + inputs.map(function (x) { return '<li data-tr>' + esc(x) + "</li>"; }).join("") + "</ul></div>" : "") +
              (outputs.length ? '<div><div class="mk">' + esc(t("outputsTitle")) + "</div><ul class=\"ctx-list\">" + outputs.map(function (x) { return '<li data-tr>' + esc(x) + "</li>"; }).join("") + "</ul></div>" : "") +
            "</div>";
        }

        $("flow").outerHTML = flowHtml(p).replace('<div class="flow">', '<div class="flow" id="flow">');
        var raci = raciHtml(p);
        $("raciWrap").innerHTML = raci.table;
        $("raciLegend").innerHTML = raci.legend;

        var bar = $("approvalBar");
        if (p.status === "review" && isAdmin()) { bar.className = "approval-bar"; bar.textContent = t("awaitingYou"); bar.hidden = false; }
        else if (p.status === "changes") { bar.className = "approval-bar is-warn"; bar.textContent = t("changesAsked") + (p.review_note ? " " + t("reviewNoteLabel") + ": " + p.review_note : ""); bar.hidden = false; }
        else bar.hidden = true;

        $("detailActions").innerHTML = detailActions(p);
        if (app && app.translateNodes) app.translateNodes($("detailCard"));
        show("listCard", false); show("editorCard", false); show("detailCard", true);
        window.scrollTo({ top: 0, behavior: "smooth" });
      }

      function load() {
        return Promise.all([app.listProcesses(), app.listMembers()]).then(function (res) {
          state.list = res[0] || []; state.members = res[1] || []; state.names = {};
          state.members.forEach(function (m) { var pr = m.profiles || {}; state.names[m.user_id] = pr.full_name || pr.email || ""; });
          renderList();
        });
      }
      /* أعمدة الملف كما في المرجع: صف لكل إجراء، وخطواته JSON في عمود واحد */
      var CSV_COLS = ["code", "name", "area", "description", "trigger", "inputs", "outputs", "frequency", "status", "steps_json"];

      function csvCell(v) {
        var s2 = String(v == null ? "" : v);
        return /[",\n\r]/.test(s2) ? '"' + s2.replace(/"/g, '""') + '"' : s2;
      }

      function downloadTemplate() {
        var sample = ["PRC-01", t("templateName"), AREAS[0] || "other", t("templateDesc"), t("templateTrigger"),
                      t("templateInputs"), t("templateOutputs"), t("templateFreq"), "draft",
                      JSON.stringify([{ id: "s1", type: "task", title: t("templateStep1"), R: "", A: "", C: "", I: "" },
                                      { id: "s2", type: "decision", title: t("templateStep2"), R: "", A: "", C: "", I: "", yesTarget: "", noTarget: "" }])];
        var csv = "\ufeff" + CSV_COLS.join(",") + "\n" + sample.map(csvCell).join(",") + "\n";
        var url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
        var a = document.createElement("a");
        a.href = url; a.download = "mrzahi-processes-template.csv";
        document.body.appendChild(a); a.click(); a.remove();
        setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
      }

      /* قارئ CSV بسيط يحترم الاقتباس والفواصل والأسطر داخل الخلية */
      function parseCsv(text) {
        var rows = [], row = [], cell = "", quoted = false;
        var src = String(text || "").replace(/^\ufeff/, "");
        for (var i = 0; i < src.length; i++) {
          var ch = src[i];
          if (quoted) {
            if (ch === '"' && src[i + 1] === '"') { cell += '"'; i++; }
            else if (ch === '"') quoted = false;
            else cell += ch;
            continue;
          }
          if (ch === '"') { quoted = true; continue; }
          if (ch === ",") { row.push(cell); cell = ""; continue; }
          if (ch === "\n" || ch === "\r") {
            if (ch === "\r" && src[i + 1] === "\n") i++;
            row.push(cell); cell = "";
            if (row.length > 1 || row[0] !== "") rows.push(row);
            row = [];
            continue;
          }
          cell += ch;
        }
        row.push(cell);
        if (row.length > 1 || row[0] !== "") rows.push(row);
        return rows;
      }

      function importCsv(file) {
        var reader = new FileReader();
        reader.onload = function () {
          var rows = parseCsv(String(reader.result || ""));
          if (rows.length < 2) { window.alert(t("importEmpty")); return; }
          var head = rows[0].map(function (h) { return String(h || "").trim().toLowerCase(); });
          var idx = {};
          CSV_COLS.forEach(function (c) { idx[c] = head.indexOf(c); });
          if (idx.name === -1) { window.alert(t("importNoName")); return; }
          var jobs = [];
          rows.slice(1).forEach(function (r) {
            var name2 = String(r[idx.name] || "").trim();
            if (!name2) return;
            var steps = [];
            if (idx.steps_json > -1) { try { steps = JSON.parse(r[idx.steps_json] || "[]") || []; } catch (e) { steps = []; } }
            var existing = state.list.filter(function (x) {
              return idx.code > -1 && x.code && x.code === String(r[idx.code] || "").trim();
            })[0];
            var row = {
              id: existing ? existing.id : undefined,
              code: idx.code > -1 ? String(r[idx.code] || "").trim() : "",
              name: name2,
              area: idx.area > -1 && AREAS.indexOf(String(r[idx.area] || "").trim()) !== -1 ? String(r[idx.area]).trim() : "other",
              description: idx.description > -1 ? String(r[idx.description] || "").trim() : "",
              trigger_text: idx.trigger > -1 ? String(r[idx.trigger] || "").trim() : "",
              inputs: idx.inputs > -1 ? String(r[idx.inputs] || "").trim() : "",
              outputs: idx.outputs > -1 ? String(r[idx.outputs] || "").trim() : "",
              frequency: idx.frequency > -1 ? String(r[idx.frequency] || "").trim() : "",
              status: idx.status > -1 && STATUSES.indexOf(String(r[idx.status] || "").trim()) !== -1 ? String(r[idx.status]).trim() : "draft",
              steps: Array.isArray(steps) ? steps : []
            };
            jobs.push(row);
          });
          if (!jobs.length) { window.alert(t("importEmpty")); return; }
          if (!window.confirm(t("importConfirm").replace("{n}", jobs.length))) return;
          /* العدد المعلن هو المحفوظ فعلا لا المحاول: كان يقول «تم استيراد 100»
             ولو رفضت القاعدة المئة كلها، فيمضي صاحبها ويحذف ملفه الأصلي. */
          var saved = 0;
          jobs.reduce(function (chain, row) {
            return chain.then(function () {
              return app.saveProcess(row).then(function () { saved += 1; }, function () { return null; });
            });
          }, Promise.resolve()).then(load).then(function () {
            window.alert(t(saved === jobs.length ? "importDone" : "importPartial")
              .replace("{n}", saved).replace("{total}", jobs.length));
          });
        };
        reader.readAsText(file, "utf-8");
      }

      function byId(id) { return state.list.filter(function (x) { return x.id === id; })[0]; }

      function setStatus(p, status, note) {
        var patch = JSON.parse(JSON.stringify(p));
        patch.status = status;
        if (note !== undefined) patch.review_note = note;
        return app.saveProcess(patch).then(load).then(function () {
          var fresh = byId(p.id);
          if (fresh) openDetail(fresh);
        });
      }

      function wire() {
        $("newBtn").addEventListener("click", function () { openEditor(null); });
        $("search").addEventListener("input", function () { state.search = this.value.trim(); renderList(); });
        $("viewGrid").addEventListener("click", function () { state.libView = "grid"; renderList(); });
        $("viewList").addEventListener("click", function () { state.libView = "list"; renderList(); });
        $("statusPills").addEventListener("click", function (e) {
          var pill = e.target.closest("[data-status]");
          if (!pill) return;
          state.statusFilter = pill.getAttribute("data-status") || "";
          renderList();
        });
        var zoomTo = function (z) {
          state.zoom = Math.max(0.5, Math.min(2, z));
          var flow = $("flow");
          if (flow) { flow.style.transform = "scale(" + state.zoom + ")"; flow.style.transformOrigin = "top center"; }
          $("zoomLevel").textContent = Math.round(state.zoom * 100) + "%";
        };
        $("zoomIn").addEventListener("click", function () { zoomTo(state.zoom + 0.15); });
        $("zoomOut").addEventListener("click", function () { zoomTo(state.zoom - 0.15); });
        $("zoomReset").addEventListener("click", function () { zoomTo(1); });
        $("tplBtn").addEventListener("click", downloadTemplate);
        $("importBtn").addEventListener("click", function () { $("importFile").click(); });
        $("importFile").addEventListener("change", function () {
          var file = this.files && this.files[0];
          this.value = "";
          if (file) importCsv(file);
        });
        $("areaPills").addEventListener("click", function (e) {
          var pill = e.target.closest("[data-area]");
          if (!pill) return;
          state.area = pill.getAttribute("data-area") || "";
          renderList();
        });
        $("libGrid").addEventListener("click", function (e) {
          var card = e.target.closest("[data-open]");
          if (!card) return;
          var p = byId(card.dataset.open);
          if (p) openDetail(p);
        });
        $("wizNext").addEventListener("click", function () {
          readForm();
          if (state.wizStep === 0 && !$("fName").value.trim()) { $("fName").focus(); return; }
          state.wizStep = Math.min(WIZ.length - 1, state.wizStep + 1);
          renderWizard();
        });
        $("wizBack").addEventListener("click", function () {
          readForm();
          state.wizStep = Math.max(0, state.wizStep - 1);
          renderWizard();
        });
        $("detailActions").addEventListener("click", function (e) {
          var btn = e.target.closest("[data-act]");
          if (!btn || !state.current) return;
          var act = btn.getAttribute("data-act"), p = state.current;
          if (act === "back") { show("detailCard", false); show("listCard", true); return; }
          if (act === "edit") { openEditor(p); return; }
          btn.disabled = true;
          var done = function () { btn.disabled = false; };
          if (act === "review") setStatus(p, "review", null).then(done, done);
          else if (act === "publish") setStatus(p, "published", null).then(done, done);
          else if (act === "unpublish") setStatus(p, "draft", null).then(done, done);
          else if (act === "reject") setStatus(p, "archived", null).then(done, done);
          else if (act === "changes") {
            var note = window.prompt(t("askChangesPrompt"), p.review_note || "");
            if (note === null) { done(); return; }
            setStatus(p, "changes", note.trim()).then(done, done);
          } else done();
        });
        $("listBody").addEventListener("click", function (e) {
          var o = e.target.closest("[data-open]"), ed = e.target.closest("[data-edit]"), tg = e.target.closest("[data-toggle]");
          if (tg) {
            var it = byId(tg.dataset.toggle);
            if (!it) return;
            var patch = JSON.parse(JSON.stringify(it));
            patch.active = it.active === false;
            tg.disabled = true;
            app.saveProcess(patch).then(load).finally(function () { tg.disabled = false; });
            return;
          }
          if (o) { e.preventDefault(); var p = byId(o.dataset.open); if (p) openDetail(p); }
          else if (ed) { var q = byId(ed.dataset.edit); if (q) openEditor(q); }
        });
        $("addStep").addEventListener("click", function () { readForm(); state.draft.steps.push(newStep()); renderSteps(); });
        $("steps").addEventListener("change", function (e) {
          var el = e.target; if (!el.dataset.f) return;
          var i = Number(el.dataset.i); state.draft.steps[i][el.dataset.f] = el.value;
          if (el.dataset.f === "type") renderSteps();
        });
        $("steps").addEventListener("input", function (e) { var el = e.target; if (el.dataset.f) state.draft.steps[Number(el.dataset.i)][el.dataset.f] = el.value; });
        $("steps").addEventListener("click", function (e) {
          var av = e.target.closest("[data-avatar]");
          if (av) {
            var ai = Number(av.dataset.i), role = av.dataset.role, id = av.dataset.member;
            var step = state.draft.steps[ai];
            step[role] = step[role] === id ? "" : id;
            av.parentElement.querySelectorAll("[data-avatar]").forEach(function (b) {
              var on = b.dataset.member === step[role];
              b.classList.toggle("is-on", on);
              b.setAttribute("aria-pressed", on ? "true" : "false");
            });
            return;
          }
          var up = e.target.closest("[data-up]"), dn = e.target.closest("[data-down]"), del = e.target.closest("[data-del]");
          var st = state.draft.steps;
          if (up) { var i = Number(up.dataset.up); if (i > 0) { var x = st[i]; st[i] = st[i - 1]; st[i - 1] = x; renderSteps(); } }
          else if (dn) { var j = Number(dn.dataset.down); if (j < st.length - 1) { var y = st[j]; st[j] = st[j + 1]; st[j + 1] = y; renderSteps(); } }
          else if (del) {
            if (st.length > 1 && window.confirm(t("confirmDeleteStep"))) { st.splice(Number(del.dataset.del), 1); renderSteps(); }
          }
        });
        $("form").addEventListener("submit", function (e) {
          e.preventDefault();
          var d = readForm();
          if (!d.name) { $("fName").focus(); return; }
          $("saveBtn").disabled = true;
          app.saveProcess(d).then(function () { return load(); }).then(function () { show("editorCard", false); show("listCard", true); })
            .catch(function () { var m = $("msg"); m.textContent = t("saveFailed"); m.hidden = false; })
            .finally(function () { $("saveBtn").disabled = false; });
        });
        $("cancelBtn").addEventListener("click", function () { show("editorCard", false); show("listCard", true); });
        $("deleteBtn").addEventListener("click", function () {
          if (!state.draft.id || !window.confirm(t("deleteConfirm"))) return;
          app.deleteProcess(state.draft.id).then(load).then(function () { show("editorCard", false); show("listCard", true); });
        });

      }
      window.__processesRefresh = function () { renderList(); };

      function boot() {
        app = window.mrzahiApp;
        if (!app || !app.ready) { show("loadingCard", false); show("unavailableCard", true); return; }
        app.ready.then(function (res) {
          show("loadingCard", false);
          if (!res || res.unavailable || app.unavailable) { show("unavailableCard", true); return; }
          if (!app.org) { show("noOrgCard", true); return; }
          loadAreas();   /* مجالات المكتبة بحسب واجهة الحساب قبل أول رسم */
          wire(); show("view", true); return load();
        }).catch(function () { show("loadingCard", false); show("unavailableCard", true); });
      }
      if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot); else boot();
    })();
  