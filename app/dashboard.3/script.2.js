      $("newOrgBtn").addEventListener("click", function () {
        var f = $("newOrgForm");
        f.hidden = !f.hidden;
        clearMsg("newOrgMsg");
        if (!f.hidden) $("newOrgName").focus();
      });
      $("newOrgCancel").addEventListener("click", function () { hide("newOrgForm"); clearMsg("newOrgMsg"); });
      $("newOrgForm").addEventListener("submit", function (ev) {
        ev.preventDefault();
        createOrgFlow($("newOrgName").value, "newOrgMsg");
      });
      $("createOrgForm").addEventListener("submit", function (ev) {
        ev.preventDefault();
        var sel = $("createOrgType");
        createOrgFlow($("createOrgName").value, "createOrgMsg", sel ? sel.value : "company");
      });

      /* الانضمام الى حساب قائم: رقم الحساب يصل صاحبه طلبا، وهو وحده من يقبل.
         (امر المهندس رعد: «ممكن يكون حاب ينضم لشركة موجودة اصلا») */
      $("joinOrgForm").addEventListener("submit", function (ev) {
        ev.preventDefault();
        var code = String($("joinOrgCode").value || "").trim();
        if (!code) { setMsg("joinOrgMsg", T("joinCodeRequired"), "error"); return; }
        clearMsg("joinOrgMsg");
        var btn = this.querySelector('button[type="submit"]');
        if (btn) btn.disabled = true;
        app.requestJoinOrg(code).then(function (res) {
          if (btn) btn.disabled = false;
          $("joinOrgCode").value = "";
          setMsg("joinOrgMsg", T("joinPending").replace("{org}", (res && res.org_name) || ""), "ok");
        }).catch(function (err) {
          if (btn) btn.disabled = false;
          var m = String((err && err.message) || "");
          if (/ORG_NOT_FOUND/.test(m)) setMsg("joinOrgMsg", T("joinNotFound"), "error");
          else if (/ALREADY_MEMBER/.test(m)) setMsg("joinOrgMsg", T("joinAlready"), "error");
          else if (/CODE_REQUIRED/.test(m)) setMsg("joinOrgMsg", T("joinCodeRequired"), "error");
          else fail(err, "joinOrgMsg");
        });
      });

      /* الطلب المعلق يظل معروضا حتى يبت فيه، فلا يعيد صاحبه ارساله كل مرة */
      window.__showPendingJoin = function () {
        if (!app || !app.myJoinRequests) return;
        app.myJoinRequests().then(function (rows) {
          var open = (rows || []).filter(function (r) { return r.status === "pending"; })[0];
          if (open) setMsg("joinOrgMsg", T("joinPending").replace("{org}", open.org_name || ""), "ok");
        }).catch(function () { /* لا طلب يعرض */ });
      };

      /* بطاقات الواجهات: الاختيار يحدد نوع الحساب المقترح ويكتب على الحساب بعد إنشائه */
      window.__renderPackCards = function () {
        var box = $("createOrgPacks"), line = $("createOrgPackLine");
        if (!box || !app || !app.listPacks) return;
        app.listPacks().then(function (rows) {
          if (!rows || rows.length < 2) { box.hidden = true; if (line) line.hidden = true; return; }
          /* حساب الفرد لا يرى إلا الواجهة الشخصية، وحساب الكيان لا يراها إطلاقا:
             من يريد ترتيب أوراقه وحده لا شأن له بشركة. */
          var typeSel = $("createOrgType");
          var personal = !!(app.isPersonType && typeSel && app.isPersonType(typeSel.value));
          rows = rows.filter(function (p) { return personal ? p.key === "individual" : p.key !== "individual"; });
          if (!rows.length) { box.hidden = true; if (line) line.hidden = true; return; }
          if (rows.length === 1) window.__wantedPack = rows[0].key;
          if (window.__wantedPack && !rows.some(function (p) { return p.key === window.__wantedPack; })) window.__wantedPack = null;
          var def = rows.filter(function (p) { return p.is_default; })[0] || rows[0];
          window.__wantedPack = window.__wantedPack || def.key;
          var html = rows.map(function (p) {
            var name = (p.names && (p.names[l] || p.names.ar)) || p.key;
            var hint = (p.hints && (p.hints[l] || p.hints.ar)) || "";
            return '<button type="button" class="pack-card' + (p.key === window.__wantedPack ? " is-on" : "") + '" data-pack="' + esc(p.key) + '" data-pack-pick="' + esc(p.key) + '" aria-pressed="' + (p.key === window.__wantedPack ? "true" : "false") + '">' +
                   '<span class="pack-icon"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="' + esc(p.icon || "") + '"/></svg></span>' +
                   '<span class="pack-name">' + esc(name) + "</span>" +
                   '<span class="pack-hint">' + esc(hint) + "</span></button>";
          }).join("");
          if (box.innerHTML !== html) box.innerHTML = html;
          box.hidden = false; if (line) line.hidden = false;
        }).catch(function () { box.hidden = true; if (line) line.hidden = true; });
      };
      $("createOrgPacks").addEventListener("click", function (ev) {
        var btn = ev.target.closest("[data-pack-pick]");
        if (!btn) return;
        window.__wantedPack = btn.getAttribute("data-pack-pick");
        this.querySelectorAll("[data-pack]").forEach(function (card) {
          var on = card.getAttribute("data-pack") === window.__wantedPack;
          card.classList.toggle("is-on", on);
          card.setAttribute("aria-pressed", on ? "true" : "false");
        });
        var nameInp = $("createOrgName"); if (nameInp) nameInp.focus();
      });

      /* مكان حفظ الملفات يختار قبل أول ورقة ترفع، لا بعد أن تضيع.
         درايف يطلب إذن Google بنقرة المستخدم نفسها، فإن رفض الإذن بقي الاختيار على المنصة. */
      (function () {
        var box = $("createOrgStore"), line = $("createOrgStoreLine");
        if (!box) return;
        /* هذا الجزء يعمل عند تحميل السكربت، وapp لا يسند إلا في boot:
           قراءته هنا كانت ترمي فتتوقف الصفحة كلها على «جاري التحميل». */
        /* لا يحذف شيء: الإخفاء قابل للرجوع، والفحص ينادى بعد جاهزية الطبقة المشتركة
           من boot. النداء وقت تحميل السكربت كان يمحو بطاقة درايف نهائيا لأن
           window.mrzahiApp لم يكن قد أسند بعد، فيختفي السؤال كله عن كل حساب جديد. */
        window.__dashDriveCheck = function () {
          if (!box) return;
          var ok = !!(window.mrzahiApp && window.mrzahiApp.driveOAuthAvailable && window.mrzahiApp.driveOAuthAvailable());
          var drive = box.querySelector('[data-store="drive"]');
          if (drive) drive.hidden = !ok;
          box.hidden = false;
          if (line) line.hidden = false;
        };
        function mark(pick) {
          box.querySelectorAll("[data-store]").forEach(function (card) {
            var on = card.getAttribute("data-store") === pick;
            card.classList.toggle("is-on", on);
            card.setAttribute("aria-pressed", on ? "true" : "false");
          });
        }
        box.addEventListener("click", function (ev) {
          var btn = ev.target.closest("[data-store-pick]");
          if (!btn || btn.disabled) return;
          var pick = btn.getAttribute("data-store-pick");
          if (pick === (app.profile && app.profile.storage_mode)) { mark(pick); return; }
          if (pick !== "drive") {
            mark("platform");
            app.updateProfile({ storage_mode: "platform" }).catch(function () { /* الافتراضي أصلا المنصة */ });
            return;
          }
          btn.disabled = true;
          function deny() { btn.disabled = false; mark("platform"); toast("storePickDriveDenied", "error"); }
          app.connectDrive()
            .then(function () { return app.updateProfile({ storage_mode: "drive" }); })
            .then(function () { btn.disabled = false; mark("drive"); })
            .catch(function (err) {
              /* الشركة غير مربوطة بعد: موافقة جوجل من الخادم (لا نافذة اذن داخل المتصفح)،
                 والعودة الى الاعدادات تكمل التفعيل */
              if (err && err.needsConnect && app.driveServerConnect) {
                return app.driveServerConnect().then(function (url) { window.location.href = url; }).catch(deny);
              }
              deny();
            });
        });
      })();

      /* أنواع الحسابات تأتي من النواة المشتركة، والاسم يتبع النوع المختار. */
      window.__fillOrgTypes = function () {
        var sel = $("createOrgType");
        if (!sel || !app || !app.entityTypes) return;
        var keep = sel.value;
        sel.innerHTML = app.entityTypes().map(function (t) {
          return '<option value="' + t.value + '">' + (t[l] || t.ar) + "</option>";
        }).join("");
        if (keep) sel.value = keep;
        var input = $("createOrgName");
        if (input) input.placeholder = T(app.isPersonType(sel.value) ? "selfNamePlaceholder" : "newOrgPlaceholder");
        /* النوع الاول شخص: اسمه من ملفه حاضر منذ اول رسم، فيبدا بنقرة لا بكتابة */
        if (input && !String(input.value || "").trim() && app.isPersonType(sel.value) && app.profile && app.profile.full_name) {
          input.value = app.profile.full_name;
        }
      };
      $("createOrgType").addEventListener("change", function () {
        /* تغيير النوع يعيد رسم بطاقات الواجهات، فلا تبقى واجهة لا تناسب النوع. */
        if (typeof window.__renderPackCards === "function") window.__renderPackCards();
        var input = $("createOrgName");
        if (!input || !app || !app.isPersonType) return;
        input.placeholder = T(app.isPersonType(this.value) ? "selfNamePlaceholder" : "newOrgPlaceholder");
        if (app.isPersonType(this.value) && !String(input.value || "").trim() && app.profile && app.profile.full_name) {
          input.value = app.profile.full_name;
        }
      });
      $("signOutBtn").addEventListener("click", function () {
        var forget = function () { var f = window.mrzahiApp && window.mrzahiApp.forgetDevice; if (f) f(); };
        var go = function () { forget(); window.location.href = "/login.html"; };
        forget();
        if (window.mrzahiAuth && window.mrzahiAuth.signOut) window.mrzahiAuth.signOut().then(go, go);
        else go();
      });

      /* ---------- stats ---------- */

      function countWhere(build) {
        var q = app.client.from("items").select("id", { count: "exact", head: true }).eq("org_id", state.org.id);
        q = build(q);
        return q.then(function (r) {
          if (r && r.error) throw new Error(r.error.message);
          return (r && typeof r.count === "number") ? r.count : 0;
        });
      }

      /* ــ مربعات اللوحة بحسب الحزمة ــ
         المقياس يختار من مفردات مغلقة في الشيفرة؛ أي معرف خارجها يتجاهل ويبقى المربع كما هو.
         الحزمة تسمي المربع وتختار أيقونته، والشيفرة وحدها تعرف كيف يحسب الرقم. */
      var TILE_ICONS = {
        list: "M3 4h18v3H3V4zm0 6.5h18v3H3v-3zM3 17h18v3H3v-3z",
        calendar: "M19 4h-1V2h-2v2H8V2H6v2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 16H5V9h14v11zM7 11h5v5H7z",
        bell: "M12 22c1.1 0 2-.9 2-2h-4c0 1.1.9 2 2 2zm6-6v-5c0-3.07-1.63-5.64-4.5-6.32V4c0-.83-.67-1.5-1.5-1.5s-1.5.67-1.5 1.5v.68C7.64 5.36 6 7.92 6 11v5l-2 2v1h16v-1l-2-2z",
        check: "M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z",
        folder: "M10 4H4a2 2 0 00-2 2v12a2 2 0 002 2h16a2 2 0 002-2V8a2 2 0 00-2-2h-8l-2-2z",
        money: "M11.8 10.9c-2.27-.59-3-1.2-3-2.15 0-1.09 1.01-1.85 2.7-1.85 1.78 0 2.44.85 2.5 2.1h2.21c-.07-1.72-1.12-3.3-3.21-3.81V3h-3v2.16c-1.94.42-3.5 1.68-3.5 3.61 0 2.31 1.91 3.46 4.7 4.13 2.5.6 3 1.48 3 2.41 0 .69-.49 1.79-2.7 1.79-2.06 0-2.87-.92-2.98-2.1h-2.2c.12 2.19 1.76 3.42 3.68 3.83V21h3v-2.15c1.95-.37 3.5-1.5 3.5-3.55 0-2.84-2.43-3.81-4.7-4.4z"
      };
      var TILE_VALUE_IDS = ["statOpenVal", "statDue7Val", "statOverdueVal", "statDoneVal"];
      var lastTiles = null;

      function packTiles() {
        var cfg = app.packCfg ? app.packCfg("tiles") : null;
        var list = cfg && (cfg[state.viewType || "default"] || cfg.default);
        return Array.isArray(list) && list.length ? list.slice(0, 4) : null;
      }

      /* الأرقام تكتب مرة واحدة بعد اكتمالها كلها: لا صفر ثم قيمة */
      function paintTiles(values) {
        var tiles = packTiles();
        if (!tiles) return;
        if (values) lastTiles = values;
        var nums = lastTiles || [];
        var cards = document.querySelectorAll(".stats-section .platform-stat-card");
        tiles.forEach(function (tile, i) {
          var card = cards[i]; if (!card) return;
          var label = card.querySelector(".platform-stat-label");
          var word = tile.label && (tile.label[l] || tile.label.ar);
          if (label && word && label.textContent !== word) { label.textContent = word; label.removeAttribute("data-i18n"); }
          if (tile.metric && card.getAttribute("data-metric") !== tile.metric) card.setAttribute("data-metric", tile.metric);
          var path = card.querySelector(".platform-stat-icon path");
          var d = TILE_ICONS[tile.icon];
          if (path && d && path.getAttribute("d") !== d) path.setAttribute("d", d);
          var val = $(TILE_VALUE_IDS[i]);
          var text = nums[i] == null ? "" : String(nums[i]);
          if (val && val.textContent !== text) val.textContent = text;
        });
      }

      /* مقاييس المربعات: نداءات مجمعة لا نداء لكل مربع */
      function tileValues(tiles) {
        var now = new Date(), nowIso = now.toISOString();
        var in7 = new Date(now.getTime() + 7 * 86400000).toISOString();
        var needPapers = tiles.some(function (t) { return String(t.metric || "").indexOf("papers") !== -1; });
        var papers = needPapers && app.orgDocumentsStatus ? app.orgDocumentsStatus().catch(function () { return null; }) : Promise.resolve(null);
        var counts = {
          "count.open": function () { return app.countItems({ status: "open" }); },
          "count.done": function () { return app.countItems({ status: "done" }); },
          "count.total": function () { return app.countItems({}); },
          "count.due7": function () { return countWhere(function (q) { return q.eq("status", "open").gte("due_at", nowIso).lte("due_at", in7); }); },
          "count.overdue": function () { return countWhere(function (q) { return q.eq("status", "open").lt("due_at", nowIso); }); }
        };
        return papers.then(function (docs) {
          var rows = (docs && docs.papers) || [];
          var paperCount = function (states) {
            return rows.filter(function (p) { return states.indexOf(p.state) !== -1; }).length;
          };
          return Promise.all(tiles.map(function (t) {
            var m = String(t.metric || "");
            /* «تنتهي قريبا» تعد ما ينتهي قريبا وحده: كانت تضم المنتهية ايضا
               بينما الضغط يفتح «تنتهي قريبا» فقط، فيختلف الرقم عما وراءه
               (رصده الوكيل 06-mrzahi-31، وقاعدة المهندس رعد ان كل رقم يفتح ما
               وراءه). المنتهية تظهر في مؤشر «اوراقي ومواعيدي» بعمودها. */
            if (m === "count.papers_expiring") return paperCount(["expiring"]);
            if (m === "count.papers_missing") return paperCount(["missing"]);
            if (m === "count.papers_valid") return paperCount(["valid", "stored"]);
            return counts[m] ? counts[m]() : 0;
          }));
        });
      }

      function loadStats() {
        var tiles = packTiles();
        if (tiles) {
          return retryOnce(function () { return tileValues(tiles); }).then(function (values) {
            safeRender("tiles", function () { paintTiles(values); });
            statsReady();
          }).catch(function (err) {
            /* رقم لم يصل يقول ذلك بشرطته: الفراغ الصامت كان يقرا كأن المربع
               صمم بلا رقم اصلا (امر المهندس رعد: «وراحت الارقام»). */
            paintTiles(tiles.map(function () { return "\u2014"; }));
            statsReady();
            fail(err);
          });
        }
        if (state.viewType) return loadViewStats();
        var now = new Date();
        var nowIso = now.toISOString();
        var in7 = new Date(now.getTime() + 7 * 86400000).toISOString();
        return Promise.all([
          app.countItems({ status: "open" }),
          countWhere(function (q) { return q.eq("status", "open").gte("due_at", nowIso).lte("due_at", in7); }),
          countWhere(function (q) { return q.eq("status", "open").lt("due_at", nowIso); }),
          app.countItems({ status: "done" })
        ]).then(function (n) {
          $("statOpenVal").textContent = String(n[0]);
          $("statDue7Val").textContent = String(n[1]);
          $("statOverdueVal").textContent = String(n[2]);
          $("statDoneVal").textContent = String(n[3]);
          statsReady();
        }).catch(function (err) { statsReady(); fail(err); });
      }

      /* أرقام اللوحة الفرعية تحسب من عناصرها هي لا من عناصر الشركة كلها. */
      function loadViewStats() {
        var now = Date.now();
        var in7 = now + 7 * 86400000;
        return app.listItems({}).then(function (rows) {
          var items = (rows || []).filter(matchesView);
          var open = 0, due7 = 0, overdue = 0, done = 0;
          items.forEach(function (it) {
            var due = it.due_at ? new Date(it.due_at).getTime() : null;
            if (it.status === "done") { done++; return; }
            if (it.status === "open") {
              open++;
              if (due && due >= now && due <= in7) due7++;
              if (due && due < now) overdue++;
            }
          });
          $("statOpenVal").textContent = String(open);
          $("statDue7Val").textContent = String(due7);
          $("statOverdueVal").textContent = String(overdue);
          statsReady();
          $("statDoneVal").textContent = String(done);
        }).catch(function (err) { statsReady(); fail(err); });
      }

      /* ---------- tabs ---------- */

      function setTab(tab) {
        /* التقويم صار دائم الظهور في العمود الجانبي، فالتبويبات لم تعد تخفيه. */
        if (document.getElementById("dashboard") && document.getElementById("dashboard").dataset.laidOut) {
          state.tab = "list";
          $("listPanel").hidden = false;
          $("calendarPanel").hidden = false;
          return;
        }
        /* التقويم لا يخفى في أي حال: القائمة والتقويم يظهران معا */
        state.tab = "list";
        $("listPanel").hidden = false;
        $("calendarPanel").hidden = false;
        [$("tabListBtn"), $("tabCalendarBtn")].forEach(function (b) {
          var active = b.dataset.tab === state.tab;
          b.classList.toggle("is-active", active);
          b.setAttribute("aria-selected", active ? "true" : "false");
        });
        try { localStorage.setItem(TAB_KEY, state.tab); } catch (e) { /* storage blocked */ }
      }
      function restoreTab() {
        var saved = "list";
        try { saved = localStorage.getItem(TAB_KEY) || "list"; } catch (e) { /* ignore */ }
        setTab(saved);
      }
      $("tabListBtn").addEventListener("click", function () { setTab("list"); });
      $("tabCalendarBtn").addEventListener("click", function () { setTab("calendar"); });

      /* ---------- selects / filters ---------- */

      function renderSelects() {
        fillSelect($("filterRecord"), recordOptions("filterAllRecords"), state.filters.record);
        fillSelect($("filterStatus"), statusOptions(true), state.filters.status);
        fillSelect($("addRecord"), recordOptions("chooseRecord"), $("addRecord").value);
        fillSelect($("addAssignee"), memberOptions(), $("addAssignee").value);
        fillSelect($("editRecord"), recordOptions("chooseRecord"), $("editRecord").value);
        fillSelect($("editAssignee"), memberOptions(), $("editAssignee").value);
        fillSelect($("editStatus"), statusOptions(false), $("editStatus").value);
        $("noRecordsHint").hidden = state.records.length > 0;
      }

      function exportColumns() {
        var items = state.items || [];
        var extra = {};
        items.forEach(function (it) { Object.keys(it.data || {}).forEach(function (k) { extra[k] = true; }); });
        var cols = [
          /* الرقم القياسي داخلي: التصدير يحمل رقم الورقة أو القضية أو المخالفة */
          { label: T("colNumber"), get: function (r) { var d = r.data || {};
              return String(r.case_number || d.number || d.violation_number || d["رقم المخالفة"] || "").trim(); } },
          { label: T("colTitle"), get: function (r) { return r.title; } },
          { label: "category", get: function (r) { return r.category; } },
          { label: T("colRecord"), get: function (r) {
            var nm = (r.records && r.records.name) || "";
            return app.recordLabel ? app.recordLabel(nm) : nm;
          } },
          { label: T("colStatus"), get: function (r) { return r.status; } },
          { label: T("colDue"), get: function (r) { return r.due_at ? app.fmtDate(r.due_at, { withTime: true }) : ""; } },
          { label: T("colAssignee"), get: function (r) { return r.assignee_id ? assigneeName(r.assignee_id) : ""; } },
          { label: T("colAmount"), get: function (r) { return r.amount; } },
          { label: T("colClient"), get: function (r) { return r.client_name; } },
          { label: T("colCaseNumber"), get: function (r) { return r.case_number; } }
        ].concat(Object.keys(extra).map(function (k) { return { label: k, get: function (r) { return (r.data || {})[k]; } }; }));
        return { items: items, cols: cols };
      }

      function exportName(ext) {
        return (state.viewType || "items") + "-" + new Date().toISOString().slice(0, 10) + "." + ext;
      }

      /* زر تصدير واحد: يضغط فيسأل عن نوع الملف، بلا زرين متجاورين */
      function exportMenu(btn, run) {
        var wrap = btn.parentNode;
        var open = wrap.querySelector(".export-menu");
        if (open) { open.remove(); return; }
        var box = document.createElement("div");
        box.className = "export-menu";
        box.innerHTML =
          '<button type="button" data-fmt="xlsx">' + esc(T("exportXlsx")) + "</button>" +
          '<button type="button" data-fmt="csv">' + esc(T("exportCsv")) + "</button>";
        wrap.appendChild(box);
        box.addEventListener("click", function (ev) {
          var pick = ev.target.closest("[data-fmt]");
          if (!pick) return;
          box.remove();
          run(pick.getAttribute("data-fmt"));
        });
        setTimeout(function () {
          document.addEventListener("click", function away(e) {
            if (!wrap.contains(e.target)) { box.remove(); document.removeEventListener("click", away); }
          });
        }, 0);
      }

      $("exportBtn").addEventListener("click", function () {
        var btn = this;
        exportMenu(btn, function (fmt) {
          var data = exportColumns();
          if (fmt === "csv") { app.exportCsv(exportName("csv"), data.items, data.cols); return; }
          btn.disabled = true;
          app.exportXlsx(exportName("xlsx"), data.items, data.cols, T(VIEW_TYPES[state.viewType] ? VIEW_TYPES[state.viewType].titleKey : "appName"))
            .catch(function () { toast("genericError", "error"); })
            .then(function () { btn.disabled = false; });
        });
      });
      $("filterRecord").addEventListener("change", function () { state.filters.record = this.value; loadItems(); });
      $("filterStatus").addEventListener("change", function () { state.filters.status = this.value; loadItems(); });

      /* الضغط على اي مربع ينقل الى قائمته مفلترة بمقياسه (امر المهندس رعد) */
      function openTileGo(metric) {
        var paper = TILE_PAPER[metric];
        if (paper) { window.location.href = "/app/documents.html#papers=" + encodeURIComponent(paper); return; }
        var want = (metric in TILE_FILTER) ? TILE_FILTER[metric] : "open";
        state.filters.status = want;
        var sel = $("filterStatus");
        if (sel) sel.value = want;
        loadItems();
        var panel = $("listPanel");
        if (panel) panel.scrollIntoView({ behavior: "smooth", block: "start" });
      }
      var statsSection = document.querySelector(".stats-section");
      if (statsSection) {
        statsSection.addEventListener("click", function (ev) {
          var card = ev.target.closest(".platform-stat-card.is-link");
          if (card) openTileGo(card.getAttribute("data-metric"));
        });
        statsSection.addEventListener("keydown", function (ev) {
          if (ev.key !== "Enter" && ev.key !== " ") return;
          var card = ev.target.closest(".platform-stat-card.is-link");
          if (!card) return;
          ev.preventDefault();
          openTileGo(card.getAttribute("data-metric"));
        });
      }
      $("filterSearch").addEventListener("input", function () {
        var v = this.value;
        if (searchTimer) clearTimeout(searchTimer);
        searchTimer = setTimeout(function () { state.filters.search = v.trim(); loadItems(); }, SEARCH_DELAY);
      });
      document.addEventListener("change", function (ev) {
        if (!ev.target) return;
        if (ev.target.id === "clientFilter") { state.clientFilter = ev.target.value || ""; renderList(); return; }
        if (ev.target.id === "expenseCatFilter") { state.expenseCat = ev.target.value || ""; renderList(); return; }
        if (ev.target.id === "expenseYearFilter") { state.expenseYear = ev.target.value || ""; renderList(); return; }
        if (ev.target.id === "contractPartyFilter") { state.contractParty = ev.target.value || ""; renderList(); return; }
        if (ev.target.id === "contractTypeFilter") { state.contractType = ev.target.value || ""; renderList(); return; }
        if (ev.target.id === "contractStateFilter") { state.contractState = ev.target.value || ""; renderList(); }
      });

      $("filterForm").addEventListener("submit", function (ev) {
        ev.preventDefault();
        if (searchTimer) clearTimeout(searchTimer);
        state.filters.search = $("filterSearch").value.trim();
        loadItems();
      });

      /* ---------- list ---------- */

      var pendingOpenItem = (function () {
        try { return new URLSearchParams(window.location.search).get("item") || ""; } catch (e) { return ""; }
      })();

      function loadItems() {
        var f = state.filters;
        var q = { recordId: f.record || undefined, search: f.search || undefined };
        if (f.status === "overdue") { q.status = "open"; q.to = new Date().toISOString(); }
        else if (f.status === "due7") {
          /* المستحقة خلال سبعة ايام: من الان الى سبعة ايام، بالحدود نفسها التي
             يعد بها مربعها فلا يختلف الرقم عن القائمة. */
          var nowD = new Date();
          q.status = "open";
          q.from = nowD.toISOString();
          q.to = new Date(nowD.getTime() + 7 * 86400000).toISOString();
        }
        else if (f.status) q.status = f.status;
        return retryOnce(function () { return app.listItems(q); }).then(function (items) {
          state.items = (items || []).filter(matchesView);
          if (f.status === "overdue" || f.status === "due7") state.items = state.items.filter(function (it) { return !!it.due_at; });
          clearMsg("listMsg");
          safeRender("list", renderList);
          if (pendingOpenItem) {
            var hit = state.items.filter(function (it) { return it.id === pendingOpenItem; })[0];
            pendingOpenItem = "";
            if (hit) openEdit(hit);
          }
        }).catch(function (err) {
          state.items = [];
          renderList();
          fail(err, "listMsg");
        });
      }

      /* بيانات العقد تقرأ من نموذجه وتكتب في data، فلا عمود جديد في القاعدة. */
      function contractRowData(prefix) {
        if (state.viewType !== "contracts") return null;
        var num = $(prefix + "ContractNumber"), type = $(prefix + "ContractType");
        var start = $(prefix + "ContractStart"), renew = $(prefix + "ContractRenewal"), notice = $(prefix + "ContractNotice");
        var out = {};
        if (num && num.value.trim()) out.contract_number = num.value.trim();
        if (type && type.value.trim()) out.contract_type = type.value.trim();
        if (start && start.value) out.contract_start = start.value;
        if (renew && renew.value) out.contract_renewal = renew.value;
        if (notice && String(notice.value).trim()) out.contract_notice = String(notice.value).trim();
        return out;
      }

      function fillContractFields(prefix, item) {
        var f = contractFields(item || {});
        var d = (item && item.data) || {};
        var num = $(prefix + "ContractNumber"), type = $(prefix + "ContractType");
        var start = $(prefix + "ContractStart"), notice = $(prefix + "ContractNotice");
        if (num) num.value = d.contract_number || "";
        if (type) type.value = d.contract_type || "";
        if (start) start.value = d.contract_start || "";
        if (notice) notice.value = d.contract_notice || "";
        fillRenewalOptions($(prefix + "ContractRenewal"), f.renewal);
      }

      /* ــ المبيعات: الصفقة بمراحلها لا بحالة «مفتوح/منجز» (امر المهندس رعد
         2026-09-17: «المبيعات تحتاج اعادة تصميم، مو معقول كل الواجهات نحصل نفس
         الشي العام الخاص بالمحامين») ــ المرحلة واحتمال الاغلاق ومصدر العميل تكتب
         في data كما تفعل العقود وصحتي بلا عمود جديد. والقيمة هي amount، والعميل
         client_name، وتاريخ الاغلاق المتوقع due_at، ورقم الصفقة case_number —
         كلها اعمدة قائمة. */
      var DEAL_STAGES = [
        { value: "lead", key: "dealStageLead" },
        { value: "contact", key: "dealStageContact" },
        { value: "proposal", key: "dealStageProposal" },
        { value: "negotiation", key: "dealStageNegotiation" },
        { value: "won", key: "dealStageWon" },
        { value: "lost", key: "dealStageLost" }
      ];
      function fillDealOptions(prefix) {
        var sel = $(prefix + "DealStage");
        if (!sel) return;
        var v = sel.value;
        sel.innerHTML = DEAL_STAGES.map(function (o) {
          return '<option value="' + o.value + '">' + T(o.key) + "</option>";
        }).join("");
        sel.value = v || "lead";
      }
      function dealStageLabel(v) {
        for (var i = 0; i < DEAL_STAGES.length; i++) if (DEAL_STAGES[i].value === v) return T(DEAL_STAGES[i].key);
        return v || "-";
      }
      function dealRowData(prefix) {
        if (state.viewType !== "deals") return null;
        var stage = $(prefix + "DealStage"), prob = $(prefix + "DealProbability"), src = $(prefix + "DealSource");
        var out = {};
        if (stage && stage.value) out.deal_stage = stage.value;
        out.deal_probability = (prob && prob.value !== "") ? Math.max(0, Math.min(100, Number(prob.value))) : null;
        if (src && src.value.trim()) out.deal_source = src.value.trim();
        return out;
      }
      function fillDealFields(prefix, item) {
        fillDealOptions(prefix);
        var d = (item && item.data) || {};
        var stage = $(prefix + "DealStage"), prob = $(prefix + "DealProbability"), src = $(prefix + "DealSource");
        if (stage) stage.value = d.deal_stage || "lead";
        if (prob) prob.value = (d.deal_probability === 0 || d.deal_probability) ? d.deal_probability : "";
        if (src) src.value = d.deal_source || "";
      }

      /* ــ «صحتي»: نموذج متخصص لا نموذج عام (امر المهندس رعد 2026-09-16: «صحتي
         ابغى اضيف عنصر، ليش الاضافة العامة الغبية، فين الاضافة المتخصصة») ــ
         النوع والجرعة والتكرار والطبيب، تكتب في data كما تفعل العقود بلا عمود
         جديد. و«التكرار» هو المفتاح data.repeat الذي يقرؤه مشغل القاعدة
         (ترحيل 0146) فينشئ الجرعة التالية وحدها عند اتمام الحالية. */
      var HEALTH_KINDS = [
        { value: "medicine", key: "healthKindMedicine", category: "دواء" },
        { value: "appointment", key: "healthKindAppointment", category: "موعد طبي" },
        { value: "lab", key: "healthKindLab", category: "فحص" },
        { value: "vaccine", key: "healthKindVaccine", category: "تطعيم" },
        { value: "fitness", key: "healthKindFitness", category: "تمرين" },
        { value: "insurance", key: "healthKindInsurance", category: "تأمين صحي" }
      ];
      /* التكرار يصف وصفة الطبيب لا درجات عامة (امر المهندس رعد 2026-09-17: «لازم
         يكون فيه التكرار حسب وصفة الطبيب»): جرعة تتكرر داخل اليوم بالساعات، ومعها
         «حتى تاريخ» فتنتهي الوصفة ولا تستمر الجرعات الى الابد. المشغل في القاعدة
         (ترحيل 0160) يفهم الخطوات السبع و data.repeat_until. */
      var HEALTH_REPEATS = [
        { value: "", key: "healthRepeatNone" },
        { value: "every_4h", key: "healthRepeat4h" },
        { value: "every_6h", key: "healthRepeat6h" },
        { value: "every_8h", key: "healthRepeat8h" },
        { value: "every_12h", key: "healthRepeat12h" },
        { value: "daily", key: "healthRepeatDaily" },
        { value: "weekly", key: "healthRepeatWeekly" },
        { value: "monthly", key: "healthRepeatMonthly" }
      ];
      function fillHealthOptions(prefix) {
        var kind = $(prefix + "HealthKind"), rep = $(prefix + "HealthRepeat");
        if (kind) {
          var kv = kind.value;
          kind.innerHTML = HEALTH_KINDS.map(function (o) {
            return '<option value="' + o.value + '">' + T(o.key) + "</option>";
          }).join("");
          if (kv) kind.value = kv;
        }
        if (rep) {
          var rv = rep.value;
          rep.innerHTML = HEALTH_REPEATS.map(function (o) {
            return '<option value="' + o.value + '">' + T(o.key) + "</option>";
          }).join("");
          if (rv) rep.value = rv;
        }
      }
      function healthRowData(prefix) {
        if (state.viewType !== "health") return null;
        var kind = $(prefix + "HealthKind"), dose = $(prefix + "HealthDose");
        var rep = $(prefix + "HealthRepeat"), who = $(prefix + "HealthProvider"), note = $(prefix + "HealthNote");
        var out = {};
        if (kind && kind.value) out.health_kind = kind.value;
        if (dose && dose.value.trim()) out.dose = dose.value.trim();
        /* repeat فارغ يمحى صراحة فلا يبقى تكرار قديم بعد الغائه */
        out.repeat = rep && rep.value ? rep.value : null;
        /* نهاية الوصفة: بعدها لا تنشا جرعة تالية. تمحى ايضا حين تفرغ */
        var until = $(prefix + "HealthUntil");
        out.repeat_until = (until && until.value) ? until.value : null;
        if (who && who.value.trim()) out.provider = who.value.trim();
        if (note && note.value.trim()) out.health_note = note.value.trim();
        return out;
      }
      /* تصنيف العنصر يتبع نوعه الصحي، فيعرف التقويم والقوائم ما هو */
      function healthCategoryFor(prefix) {
        if (state.viewType !== "health") return null;
        var kind = $(prefix + "HealthKind");
        if (!kind || !kind.value) return null;
        for (var i = 0; i < HEALTH_KINDS.length; i++) if (HEALTH_KINDS[i].value === kind.value) return HEALTH_KINDS[i].category;
        return null;
      }
      function fillHealthFields(prefix, item) {
        fillHealthOptions(prefix);
        var d = (item && item.data) || {};
        var kind = $(prefix + "HealthKind"), dose = $(prefix + "HealthDose");
        var rep = $(prefix + "HealthRepeat"), who = $(prefix + "HealthProvider"), note = $(prefix + "HealthNote");
        if (kind) kind.value = d.health_kind || "medicine";
        if (dose) dose.value = d.dose || "";
        if (rep) rep.value = d.repeat || "";
        var until = $(prefix + "HealthUntil");
        if (until) until.value = d.repeat_until || "";
        if (who) who.value = d.provider || "";
        if (note) note.value = d.health_note || "";
      }
      function clearHealthFields(prefix) {
        ["HealthDose", "HealthProvider", "HealthNote"].forEach(function (k) {
          var el = $(prefix + k);
          if (el) el.value = "";
        });
        var rep = $(prefix + "HealthRepeat");
        if (rep) rep.value = "";
      }

      function clearContractFields(prefix) {
        ["ContractNumber", "ContractType", "ContractStart", "ContractNotice"].forEach(function (k) {
          var el = $(prefix + k);
          if (el) el.value = "";
        });
        var renew = $(prefix + "ContractRenewal");
        if (renew) renew.value = "";
      }

      function numOrNull(v) {
        var s = String(v == null ? "" : v).trim();
        if (!s) return null;
        var n = Number(s);
        return isFinite(n) ? n : null;
      }

      function actionBtn(item, action, key, extra) {
        return '<button type="button" class="chat-option-btn' + (extra ? " " + extra : "") + '" data-action="' + action +
          '" data-id="' + esc(item.id) + '">' + esc(T(key)) + "</button>";
      }

      /* ---------- جدول المخالفات ---------- */

      function dataOf(item, keys) {
        var d = item.data || {};
        for (var i = 0; i < keys.length; i++) {
          var k = keys[i];
          if (d[k] !== undefined && d[k] !== null && String(d[k]).trim() !== "") return String(d[k]).trim();
        }
        return "";
      }

      function violationFields(item) {
        return {
          number: dataOf(item, ["violation_number", "رقم المخالفة"]) || item.case_number || "",
          date: dataOf(item, ["violation_date", "تاريخ المخالفة"]),
          issuer: dataOf(item, ["location", "جهة اصدار المخالفة", "جهة الإصدار"]),
          vtype: dataOf(item, ["نوع المخالفة", "violation_type"]),
          objection: dataOf(item, ["حالة التظلم", "التظلم امام الامانة", "objection"]),
          client: (app.clientDisplayName ? app.clientDisplayName(item) : item.client_name) || dataOf(item, ["الشركة", "client"]),
          caseNumber: item.case_number || dataOf(item, ["رقم الدعوى", "رقم القضية"])
        };
      }

      function money(n) {
        var v = Number(n);
        if (!isFinite(v) || !v) return "-";
        return app.fmtAmount(v) + ' <span class="sar-symbol" aria-label="ريال سعودي"></span>';
      }

      function shortDate(v) {
        if (!v) return "-";
        var d = new Date(v);
        if (!isNaN(d.getTime())) return app.fmtDate(d.toISOString());
        return String(v);
      }

      function renderClientFilter(items) {
        var sel = $("clientFilter");
        if (!sel) return;
        var names = {};
        items.forEach(function (it) {
          var shown = (app.clientDisplayName ? app.clientDisplayName(it) : it.client_name) || "";
          if (shown) names[shown] = true;
        });
        var list = Object.keys(names).sort();
        var current = state.clientFilter || "";
        paintEl(sel).html = '<option value="">' + esc(T("allClients")) + "</option>" +
          list.map(function (n) { return '<option value="' + esc(n) + '">' + esc(n) + "</option>"; }).join("");
        sel.value = current;
      }

      function renderTotals(items) {
        var box = $("violationTotals");
        if (!box) return;
        var total = items.length;
        var sum = 0, unpaidSum = 0, overdue = 0;
        var now = Date.now();
        items.forEach(function (it) {
          var amt = Number(it.amount) || 0;
          sum += amt;
          if (it.status !== "done") unpaidSum += amt;
          if (it.status === "open" && it.due_at && new Date(it.due_at).getTime() < now) overdue++;
        });
        paintEl(box).html =
          '<div class="total-card"><span class="total-label">' + esc(T("totalCount")) + '</span><span class="total-value">' + esc(String(total)) + "</span></div>" +
          '<div class="total-card"><span class="total-label">' + esc(T("totalAmount")) + '</span><span class="total-value">' + money(sum) + "</span></div>" +
          '<div class="total-card"><span class="total-label">' + esc(T("totalUnpaid")) + '</span><span class="total-value">' + money(unpaidSum) + "</span></div>" +
          '<div class="total-card"><span class="total-label">' + esc(T("totalOverdue")) + '</span><span class="total-value">' + esc(String(overdue)) + "</span></div>";
      }

      /* ---------- العقود: شاشتها تقرأ ما يقرؤه صاحب العقد ----------
         العقد ليس عنصرا بموعد، بل مدة بين تاريخين لها قيمة وطرف وتجديد ومهلة إشعار.
         المهلة هي بيت القصيد: من يفوتها يتجدد عليه العقد سنة كاملة بلا إرادته. */

      var CONTRACT_RENEWALS = ["auto", "manual", "none"];
      var CONTRACT_RENEWAL_KEYS = { auto: "renewalAuto", manual: "renewalManual", none: "renewalNone" };
      var CONTRACT_SOON_DAYS = 90;   /* بلا مهلة مكتوبة: تسعون يوما تكفي لقرار التجديد */

      function contractFields(item) {
        var d = item.data || {};
        var renew = String(d.contract_renewal || d["التجديد"] || "").trim();
        return {
          number: dataOf(item, ["contract_number", "رقم العقد"]) || item.case_number || "",
          party: (app.clientDisplayName ? app.clientDisplayName(item) : item.client_name) || dataOf(item, ["الطرف الآخر", "party"]),
          ctype: dataOf(item, ["contract_type", "نوع العقد"]) || item.category || "",
          start: dataOf(item, ["contract_start", "تاريخ البدء", "تاريخ التوقيع", "start_date"]),
          notice: dataOf(item, ["contract_notice", "مهلة الإشعار"]),
          renewal: CONTRACT_RENEWAL_KEYS[renew] ? renew : ""
        };
      }

      function contractNoticeDays(f) {
        var n = Number(f.notice);
        return isFinite(n) && n > 0 ? n : CONTRACT_SOON_DAYS;
      }

      /* ثلاث حالات لا أكثر: ساري، وقربت مهلته، ومنته. */
      function contractState(item) {
        if (item.status === "done" || item.status === "cancelled") return "ended";
        if (!item.due_at) return "active";
        var due = new Date(item.due_at).getTime();
        if (!isFinite(due)) return "active";
        var now = Date.now();
        if (due < now) return "ended";
        return due - now <= contractNoticeDays(contractFields(item)) * 86400000 ? "soon" : "active";
      }

      var CONTRACT_STATE_KEYS = { active: "contractActive", soon: "contractSoon", ended: "contractEnded" };

      function fillRenewalOptions(sel, value) {
        if (!sel) return;
        paintEl(sel).html = '<option value="">' + esc(T("renewalNone")) + "</option>" +
          CONTRACT_RENEWALS.map(function (k) {
            return '<option value="' + k + '">' + esc(T(CONTRACT_RENEWAL_KEYS[k])) + "</option>";
          }).join("");
        sel.value = value || "";
      }

      function renderContractFilters(items) {
        var parties = {}, types = {};
        items.forEach(function (it) {
          var f = contractFields(it);
          if (f.party) parties[f.party] = true;
          if (f.ctype) types[f.ctype] = true;
        });
        var party = $("contractPartyFilter");
        if (party) {
          var cur = state.contractParty || "";
          paintEl(party).html = '<option value="">' + esc(T("allParties")) + "</option>" +
            Object.keys(parties).sort().map(function (n) { return '<option value="' + esc(n) + '">' + esc(n) + "</option>"; }).join("");
          party.value = cur;
        }
        var type = $("contractTypeFilter");
        if (type) {
          var curT = state.contractType || "";
          paintEl(type).html = '<option value="">' + esc(T("allContractTypes")) + "</option>" +
            Object.keys(types).sort().map(function (n) { return '<option value="' + esc(n) + '">' + esc(n) + "</option>"; }).join("");
          type.value = curT;
        }
        var st = $("contractStateFilter");
        if (st) {
          var curS = state.contractState || "";
          paintEl(st).html = '<option value="">' + esc(T("allContractStates")) + "</option>" +
            ["active", "soon", "ended"].map(function (k) {
              return '<option value="' + k + '">' + esc(T(CONTRACT_STATE_KEYS[k])) + "</option>";
            }).join("");
          st.value = curS;
        }
        var list = $("contractTypeSuggest");
        if (list) paintEl(list).html = Object.keys(types).sort().map(function (n) { return '<option value="' + esc(n) + '"></option>'; }).join("");
      }

      function renderContractTotals(items) {
        var box = $("contractTotals");
        if (!box) return;
        var sum = 0, soon = 0, ended = 0;
        items.forEach(function (it) {
          sum += Number(it.amount) || 0;
          var st = contractState(it);
          if (st === "soon") soon++;
          if (st === "ended") ended++;
        });
        paintEl(box).html =
          '<div class="total-card"><span class="total-label">' + esc(T("totalContracts")) + '</span><span class="total-value">' + esc(String(items.length)) + "</span></div>" +
          '<div class="total-card"><span class="total-label">' + esc(T("totalContractValue")) + '</span><span class="total-value">' + money(sum) + "</span></div>" +
          '<div class="total-card"><span class="total-label">' + esc(T("totalContractSoon")) + '</span><span class="total-value">' + esc(String(soon)) + "</span></div>" +
          '<div class="total-card"><span class="total-label">' + esc(T("totalContractEnded")) + '</span><span class="total-value">' + esc(String(ended)) + "</span></div>";
      }

      function renderContracts() {
        renderContractFilters(state.items);
        var items = state.items.filter(function (it) {
          var f = contractFields(it);
          if (state.contractParty && f.party !== state.contractParty) return false;
          if (state.contractType && f.ctype !== state.contractType) return false;
          if (state.contractState && contractState(it) !== state.contractState) return false;
          return true;
        });
        renderContractTotals(items);
        var body = $("contractsBody");
        body.innerHTML = "";
        $("contractsWrap").hidden = items.length === 0;
        $("emptyList").hidden = items.length > 0;
        items.forEach(function (item) {
          var f = contractFields(item);
          var sk = statusKeyOf(item);
          var cs = contractState(item);
          var tr = document.createElement("tr");
          tr.innerHTML =
            '<td class="cell-num">' + esc(f.number || "-") + "</td>" +
            '<td><span class="item-title" data-tr>' + esc(item.title) + "</span></td>" +
            '<td data-tr>' + esc(f.party || "-") + "</td>" +
            "<td>" + esc(f.ctype || "-") + "</td>" +
            '<td class="cell-num">' + esc(shortDate(f.start)) + "</td>" +
            '<td class="cell-num">' + (item.due_at ? esc(app.fmtDate(item.due_at)) : "-") + "</td>" +
            '<td class="cell-num">' + (item.due_at
              ? '<span class="item-cat due-left" data-due="' + esc(item.due_at) + '"></span>'
              : "-") + "</td>" +
            '<td class="cell-num">' + money(item.amount) + "</td>" +
            "<td>" + (f.renewal ? esc(T(CONTRACT_RENEWAL_KEYS[f.renewal])) : "-") +
              (f.notice ? ' <span class="item-cat">' + esc(T("noticeShort").replace("%s", f.notice)) + "</span>" : "") + "</td>" +
            '<td><span class="status-' + sk + '">' + esc(T(CONTRACT_STATE_KEYS[cs])) + "</span></td>" +
            '<td><div class="chat-options row-actions">' +
              (item.status === "done" ? actionBtn(item, "reopen", "actionReopen") : actionBtn(item, "done", "actionDone")) +
              actionBtn(item, "edit", "actionEdit") +
              actionBtn(item, "delete", "actionDelete", "is-danger") +
            "</div></td>";
          body.appendChild(tr);
        });
        translateView();
      }

      /* حقول العقد تظهر في شاشة العقود وحدها، في نموذجي الإضافة والتعديل معا. */
      function applyViewFields() {
        document.querySelectorAll("[data-view]").forEach(function (el) {
          el.hidden = el.getAttribute("data-view") !== state.viewType;
        });
        /* صحتي: سجلها يجهز وحده فلا يسال صاحبه «اي سجل؟» قبل ان يضيف دواء */
        document.querySelectorAll('[data-field="record"]').forEach(function (el) {
          if (state.viewType === "health") el.hidden = true;
        });
        /* الفواتير: مبلغ الفاتورة يحسب من اساسها وضريبتها، فلا يسال عن المبلغ مرتين */
        document.querySelectorAll('[data-field="amount"]').forEach(function (el) {
          if (state.viewType === "invoices") el.hidden = true;
        });
      }

      /* سجل «صحتي»: يبحث عنه فان لم يوجد انشئ مرة واحدة، ثم يختار في النموذجين */
      var healthRecordAsked = false;
      function healthRecordName() { return T("healthRecordName"); }
      function pickHealthRecord() {
        var names = ["صحتي", "Health", "My health", "Ma sante", "میری صحت", healthRecordName()];
        for (var i = 0; i < (state.records || []).length; i++) {
          if (names.indexOf(state.records[i].name) !== -1) return state.records[i];
        }
        return null;
      }
      function selectHealthRecord(rec) {
        if (!rec) return;
        ["addRecord", "editRecord"].forEach(function (id) {
          var sel = $(id);
          if (sel) sel.value = rec.id;
        });
      }
      function ensureHealthRecord() {
        var rec = pickHealthRecord();
        if (rec) { selectHealthRecord(rec); return Promise.resolve(rec); }
        if (healthRecordAsked) return Promise.resolve(null);
        healthRecordAsked = true;
        return app.createRecord({ name: healthRecordName() }).then(function (t) {
          state.records.push(t);
          renderSelects();
          selectHealthRecord(t);
          return t;
        }).catch(function () { healthRecordAsked = false; return null; });
      }

      /* ---------- «صحتي»: شاشتها الخاصة ---------- */
      /* كل ما يخص صحة صاحبها: دواء وجرعته وتكراره، موعد طبيب، فحص، تطعيم،
         اشتراك نادي وحصصه، تامين صحي. المنتظم يحمل data.repeat فتنشا مرته
         التالية وحدها عند اتمام الحالية (مشغل القاعدة، ترحيل 0146). */
      var HEALTH_STATES = ["", "today", "upcoming", "overdue", "done"];
      var HEALTH_STATE_KEYS = { "": "healthStateAll", today: "healthStateToday", upcoming: "healthStateUpcoming", overdue: "healthStateOverdue", done: "healthStateDone" };

      function healthFields(item) {
        var d = (item && item.data) || {};
        var kind = d.health_kind || "";
        if (!kind) {
          /* عنصر سجل قبل النموذج المتخصص: نوعه يستنتج من تصنيفه لا يترك فارغا */
          var cat = String((item && item.category) || "");
          if (/نادي|جيم|تمرين|لياقة|gym|fitness/i.test(cat)) kind = "fitness";
          else if (/تطعيم|لقاح|vaccine/i.test(cat)) kind = "vaccine";
          else if (/فحص|تحليل|اشعة|lab|test/i.test(cat)) kind = "lab";
          else if (/موعد|مراجعة|طبيب|عيادة|appointment|clinic|doctor/i.test(cat)) kind = "appointment";
          else if (/تامين|تأمين|insurance/i.test(cat)) kind = "insurance";
          else kind = "medicine";
        }
        return { kind: kind, dose: d.dose || "", repeat: d.repeat || "", provider: d.provider || item.client_name || "", note: d.health_note || "" };
      }

      function healthKindLabel(kind) {
        for (var i = 0; i < HEALTH_KINDS.length; i++) if (HEALTH_KINDS[i].value === kind) return T(HEALTH_KINDS[i].key);
        return kind || "-";
      }

      function healthRepeatLabel(rep) {
        for (var i = 0; i < HEALTH_REPEATS.length; i++) if (HEALTH_REPEATS[i].value === (rep || "")) return T(HEALTH_REPEATS[i].key);
        return rep || "-";
      }

      function healthState(item) {
        if (item.status === "done") return "done";
        if (!item.due_at) return "upcoming";
        var due = new Date(item.due_at), now = new Date();
        if (isNaN(due.getTime())) return "upcoming";
        if (due < now) return "overdue";
        if (due.toDateString() === now.toDateString()) return "today";
        return "upcoming";
      }

      function renderHealthFilters(items) {
        var kinds = {};
        items.forEach(function (it) { kinds[healthFields(it).kind] = true; });
        var kindOpts = [{ value: "", label: T("healthKindAll") }];
        HEALTH_KINDS.forEach(function (k) { if (kinds[k.value]) kindOpts.push({ value: k.value, label: T(k.key) }); });
        fillSelect($("healthKindFilter"), kindOpts, state.healthKind || "");
        fillSelect($("healthStateFilter"), HEALTH_STATES.map(function (v) { return { value: v, label: T(HEALTH_STATE_KEYS[v]) }; }), state.healthState || "");
      }

      /* المجاميع بمكون المنصة نفسه (total-card كما في العقود والمخالفات):
         بطاقة لكل رقم، لا نص ملتصق برقم (امر المهندس رعد: «عدل التصميم السيء»). */
      function renderHealthTotals(items) {
        var box = $("healthTotals");
        if (!box) return;
        var today = 0, overdue = 0, regular = 0, subsAmount = 0, subs = 0;
        items.forEach(function (it) {
          var f = healthFields(it), st = healthState(it);
          if (st === "today") today++;
          if (st === "overdue") overdue++;
          if (f.repeat) regular++;
          if (f.kind === "fitness" || f.kind === "insurance") { subs++; subsAmount += Number(it.amount) || 0; }
        });
        paintEl(box).html =
          '<div class="total-card"><span class="total-label">' + esc(T("healthTotalToday")) + '</span><span class="total-value">' + esc(String(today)) + "</span></div>" +
          '<div class="total-card"><span class="total-label">' + esc(T("healthTotalOverdue")) + '</span><span class="total-value">' + esc(String(overdue)) + "</span></div>" +
          '<div class="total-card"><span class="total-label">' + esc(T("healthTotalRegular")) + '</span><span class="total-value">' + esc(String(regular)) + "</span></div>" +
          '<div class="total-card"><span class="total-label">' + esc(T("healthTotalSubs")) + '</span><span class="total-value">' + (subsAmount ? money(subsAmount) : esc(String(subs))) + "</span></div>";
      }

      function renderHealth() {
        renderHealthFilters(state.items);
        var items = state.items.filter(function (it) {
          var f = healthFields(it);
          if (state.healthKind && f.kind !== state.healthKind) return false;
          if (state.healthState && healthState(it) !== state.healthState) return false;
          return true;
        });
        renderHealthTotals(items);
        var body = $("healthBody");
        body.innerHTML = "";
        $("healthWrap").hidden = items.length === 0;
        $("emptyList").hidden = items.length > 0;
        items.forEach(function (item) {
          var f = healthFields(item);
          var sk = statusKeyOf(item);
          var tr = document.createElement("tr");
          tr.innerHTML =
            '<td><span class="item-title" data-tr>' + esc(item.title) + "</span>" +
              (f.note ? ' <span class="item-cat" data-tr>' + esc(f.note) + "</span>" : "") + "</td>" +
            "<td>" + esc(healthKindLabel(f.kind)) + "</td>" +
            '<td data-tr>' + esc(f.dose || "-") + "</td>" +
            "<td>" + (f.repeat ? '<span class="item-cat">' + esc(healthRepeatLabel(f.repeat)) + "</span>" : "-") + "</td>" +
            '<td class="cell-num">' + (item.due_at ? esc(app.fmtDate(item.due_at)) : "-") + "</td>" +
            '<td class="cell-num">' + (item.due_at
              ? '<span class="item-cat due-left" data-due="' + esc(item.due_at) + '"></span>'
              : "-") + "</td>" +
            '<td data-tr>' + esc(f.provider || "-") + "</td>" +
            '<td class="cell-num">' + money(item.amount) + "</td>" +
            '<td><span class="status-' + sk + '">' + esc(T(HEALTH_STATE_KEYS[healthState(item)])) + "</span></td>" +
            '<td><div class="chat-options row-actions">' +
              (item.status === "done" ? actionBtn(item, "reopen", "actionReopen") : actionBtn(item, "done", "actionDone")) +
              actionBtn(item, "edit", "actionEdit") +
              actionBtn(item, "delete", "actionDelete", "is-danger") +
            "</div></td>";
          body.appendChild(tr);
        });
        translateView();
      }

      (function wireHealthFilters() {
        var kind = $("healthKindFilter"), st = $("healthStateFilter");
        if (kind) kind.addEventListener("change", function () { state.healthKind = this.value; renderHealth(); });
        if (st) st.addEventListener("change", function () { state.healthState = this.value; renderHealth(); });
      })();

      /* ــ المالية: الفاتورة لا «بند مصروف» ــ
         حقولها كلها في data كما تفعل العقود وصحتي، و items.amount يبقى الاجمالي
         شامل الضريبة فلا تتاثر مجاميع اللوحة ولا التقويم ولا المربعات الاربعة.
         تاريخ الاستحقاق هو due_at نفسه، فالفاتورة تدخل التقويم والتذكير مجانا. */

      var FIN_VAT_RATE = 0.15;
      var FIN_DIRS = [
        { value: "in",  key: "financeDirIn",  shortKey: "financeDirInShort",  category: "فاتورة مدينة" },
        { value: "out", key: "financeDirOut", shortKey: "financeDirOutShort", category: "فاتورة دائنة" }
      ];
      /* الضريبة 15% كقاعدة المشروع: المنشات تضاف عليها (وحزمة المالية لا تقبل
         حساب فرد اصلا)، و«شامل» لمن كتب سعرا شاملا، و«معفاة» لما لا ضريبة عليه. */
      var FIN_VAT_MODES = [
        { value: "exclusive", key: "financeVatExclusive" },
        { value: "inclusive", key: "financeVatInclusive" },
        { value: "exempt",    key: "financeVatExempt" }
      ];
      var FIN_STATES = ["", "due", "partial", "overdue", "collected", "cancelled"];
      var FIN_STATE_KEYS = {
        "": "financeStateAll", due: "financeStateDue", partial: "financeStatePartial",
        overdue: "financeStateOverdue", collected: "financeStateCollected", cancelled: "financeStateCancelled"
      };

      function fin2(n) { return Math.round((Number(n) || 0) * 100) / 100; }

      /* تحسب مرة واحدة عند الحفظ وتخزن، ولا تحسب من جديد عند القراءة ابدا
         (قاعدة الضريبة في المشروع، وجدول payments يخزنها هكذا). */
      function finVatSplit(entered, mode) {
        var v = Number(entered) || 0, base, vat, rate = FIN_VAT_RATE;
        if (mode === "exempt") { base = fin2(v); vat = 0; rate = 0; }
        else if (mode === "inclusive") { base = fin2(v / (1 + rate)); vat = fin2(v - base); }
        else { base = fin2(v); vat = fin2(v * rate); }
        return { base: base, vat: vat, total: fin2(base + vat), rate: rate };
      }

      function financeFields(item) {
        var d = (item && item.data) || {};
        var total = d.total_sar != null ? Number(d.total_sar) : (Number(item && item.amount) || 0);
        var paid = Number(d.paid_sar) || 0;
        return {
          number: dataOf(item, ["invoice_number", "رقم الفاتورة"]) || item.case_number || "",
          dir: d.fin_dir === "out" ? "out" : "in",
          party: (app.clientDisplayName ? app.clientDisplayName(item) : item.client_name) ||
                 dataOf(item, ["الجهة", "العميل", "المورد", "party"]),
          issued: dataOf(item, ["invoice_date", "تاريخ الاصدار", "تاريخ الفاتورة"]),
          vatMode: d.vat_mode || "",   /* فارغ = عنصر سابق لهذه الشاشة، لا ضريبة مصرحة له */
          base: d.base_sar != null ? Number(d.base_sar) : total,
          vat: Number(d.vat_sar) || 0,
          total: total,
          paid: paid,
          remain: fin2(total - paid),
          paidAt: d.paid_at || "",
          method: dataOf(item, ["pay_method", "طريقة السداد", "طريقة الدفع"])
        };
      }

      /* ما يكتبه صاحبها في خانة «مبلغ الفاتورة»: الاجمالي ان كان السعر شاملا،
         والاساس فيما عداه. فما يقرؤه هو ما كتبه لا رقما اخر. */
      function finEntered(f) { return f.vatMode === "inclusive" ? f.total : f.base; }

      function financeState(item) {
        if (item.status === "cancelled") return "cancelled";
        var f = financeFields(item);
        if (item.status === "done" || (f.total > 0 && f.remain <= 0)) return "collected";
        if (item.due_at && new Date(item.due_at).getTime() < Date.now()) return "overdue";
        if (f.paid > 0) return "partial";
        return "due";
      }

      function finDirLabel(dir, short) {
        for (var i = 0; i < FIN_DIRS.length; i++) {
          if (FIN_DIRS[i].value === dir) return T(short ? FIN_DIRS[i].shortKey : FIN_DIRS[i].key);
        }
        return "-";
      }

      function fillFinanceOptions(prefix) {
        fillSelect($(prefix + "FinDir"),
          FIN_DIRS.map(function (o) { return { value: o.value, label: T(o.key) }; }),
          ($(prefix + "FinDir") && $(prefix + "FinDir").value) || "in");
        fillSelect($(prefix + "FinVat"),
          FIN_VAT_MODES.map(function (o) { return { value: o.value, label: T(o.key) }; }),
          ($(prefix + "FinVat") && $(prefix + "FinVat").value) || "exclusive");
      }

      function financeRowData(prefix) {
        if (state.viewType !== "invoices") return null;
        var num = $(prefix + "FinNumber"), dir = $(prefix + "FinDir"), issued = $(prefix + "FinIssued");
        var vatSel = $(prefix + "FinVat"), amount = $(prefix + "FinAmount");
        var paidEl = $(prefix + "FinPaid"), paidAt = $(prefix + "FinPaidAt"), method = $(prefix + "FinMethod");
        var mode = (vatSel && vatSel.value) || "exclusive";
        var split = finVatSplit(amount ? amount.value : 0, mode);
        var paid = Math.max(0, Number(numOrNull(paidEl ? paidEl.value : "")) || 0);
        var prev = (prefix === "edit" && state.editing && state.editing.data) || {};
        var out = {
          fin_dir: (dir && dir.value === "out") ? "out" : "in",
          vat_mode: mode,
          vat_rate: split.rate,
          base_sar: split.base,
          vat_sar: split.vat,
          total_sar: split.total,
          paid_sar: paid
        };
        if (num && num.value.trim()) out.invoice_number = num.value.trim();
        if (issued && issued.value) out.invoice_date = issued.value;
        if (method && method.value.trim()) out.pay_method = method.value.trim();
        /* يوم التحصيل: عليه يقوم «المحصل هذا الشهر» و«متوسط ايام التحصيل». يكتب
           كما كتبه صاحبه، وان حصل مبلغا ولم يكتب يوما فاليوم، وان عاد المحصل الى
           صفر محي التاريخ فلا يبقى تحصيل لا مقابل له. */
        if (paidAt && paidAt.value) out.paid_at = paidAt.value;
        else if (!paid) out.paid_at = null;
        else if (paid > (Number(prev.paid_sar) || 0)) out.paid_at = new Date().toISOString().slice(0, 10);
        return out;
      }

      /* تصنيف العنصر يتبع اتجاه فاتورته، فيعرف التقويم والقوائم ما هو */
      function financeCategoryFor(prefix) {
        if (state.viewType !== "invoices") return null;
        var dir = $(prefix + "FinDir");
        var v = (dir && dir.value) || "in";
        for (var i = 0; i < FIN_DIRS.length; i++) if (FIN_DIRS[i].value === v) return FIN_DIRS[i].category;
        return null;
      }

      function fillFinanceFields(prefix, item) {
        fillFinanceOptions(prefix);
        var f = financeFields(item || {});
        var dir = $(prefix + "FinDir"), vatSel = $(prefix + "FinVat");
        var num = $(prefix + "FinNumber"), issued = $(prefix + "FinIssued");
        var amount = $(prefix + "FinAmount"), paidEl = $(prefix + "FinPaid");
        var paidAt = $(prefix + "FinPaidAt"), method = $(prefix + "FinMethod");
        if (num) num.value = f.number || "";
        if (dir) dir.value = f.dir;
        if (issued) issued.value = f.issued || "";
        /* عنصر انشئ قبل هذه الشاشة يفتح «معفاة» فلا يزيد مبلغه 15% بحفظة واحدة،
           والفاتورة الجديدة تفتح على «تضاف 15%» كقاعدة المنشات في المشروع. */
        if (vatSel) vatSel.value = f.vatMode || ((item && item.id) ? "exempt" : "exclusive");
        if (amount) amount.value = (f.total || f.base) ? String(finEntered(f)) : "";
        if (paidEl) paidEl.value = f.paid ? String(f.paid) : "";
        if (paidAt) paidAt.value = f.paidAt || "";
        if (method) method.value = f.method || "";
      }

      function clearFinanceFields(prefix) {
        ["FinNumber", "FinIssued", "FinAmount", "FinPaid", "FinPaidAt", "FinMethod"].forEach(function (k) {
          var el = $(prefix + k);
          if (el) el.value = "";
        });
        var dir = $(prefix + "FinDir");
        if (dir) dir.value = "in";
        var vatSel = $(prefix + "FinVat");
        if (vatSel) vatSel.value = "exclusive";
      }

      /* طرق السداد تقترح ما استعمله صاحب الحساب فعلا، وتبقى قابلة للكتابة الحرة */
      function renderFinanceMethodSuggest(items) {
        var box = $("finMethodSuggest");
        if (!box) return;
        var seen = {}, list = [];
        items.forEach(function (it) {
          var m = financeFields(it).method;
          if (!m || seen[m]) return;
          seen[m] = true; list.push(m);
        });
        paintEl(box).html = list.sort().map(function (m) { return '<option value="' + esc(m) + '"></option>'; }).join("");
      }

      function renderFinanceFilters(items) {
        fillSelect($("financeDirFilter"),
          [{ value: "", label: T("financeDirAll") }].concat(FIN_DIRS.map(function (o) {
            return { value: o.value, label: T(o.shortKey) };
          })), state.financeDir || "");
        fillSelect($("financeStateFilter"),
          FIN_STATES.map(function (v) { return { value: v, label: T(FIN_STATE_KEYS[v]) }; }),
          state.financeState || "");
        var parties = {};
        items.forEach(function (it) { var p = financeFields(it).party; if (p) parties[p] = true; });
        fillSelect($("financePartyFilter"),
          [{ value: "", label: T("financePartyAll") }].concat(Object.keys(parties).sort().map(function (p) {
            return { value: p, label: p };
          })), state.financeParty || "");
      }

      function financeFiltered(items) {
        return items.filter(function (it) {
          var f = financeFields(it);
          if (state.financeDir && f.dir !== state.financeDir) return false;
          if (state.financeState && financeState(it) !== state.financeState) return false;
          if (state.financeParty && f.party !== state.financeParty) return false;
          return true;
        });
      }

      /* مجاميع المحاسب: كم فاتورة، وكم لنا، وكم علينا، وكم تاخر */
      function renderFinanceTotals(items) {
        var box = $("financeTotals");
        if (!box) return;
        var recv = 0, pay = 0, late = 0, now = Date.now();
        items.forEach(function (it) {
          var f = financeFields(it), st = financeState(it);
          if (st === "collected" || st === "cancelled") return;
          if (f.dir === "in") recv += f.remain; else pay += f.remain;
          if (it.due_at && new Date(it.due_at).getTime() < now) late += f.remain;
        });
        paintEl(box).html =
          '<div class="total-card"><span class="total-label">' + esc(T("finTotalCount")) + '</span><span class="total-value">' + esc(String(items.length)) + "</span></div>" +
          '<div class="total-card"><span class="total-label">' + esc(T("finTotalReceivable")) + '</span><span class="total-value">' + money(recv) + "</span></div>" +
          '<div class="total-card"><span class="total-label">' + esc(T("finTotalPayable")) + '</span><span class="total-value">' + money(pay) + "</span></div>" +
          '<div class="total-card"><span class="total-label">' + esc(T("finTotalOverdue")) + '</span><span class="total-value">' + money(late) + "</span></div>";
      }

      /* اكبر المدينين: الجهات التي عليها مبلغ متبق، بالمبلغ لا بعدد الفواتير */
      function debtorBreakdown(items) {
        var sums = {};
        items.forEach(function (it) {
          var f = financeFields(it), st = financeState(it);
          if (f.dir !== "in" || st === "collected" || st === "cancelled" || f.remain <= 0) return;
          var name = f.party || T("noAssignee");
          sums[name] = (sums[name] || 0) + f.remain;
        });
        return Object.keys(sums).map(function (k) { return { label: k, value: Math.round(sums[k]) }; })
          .sort(function (a, b) { return b.value - a.value; }).slice(0, 6);
      }

      function renderFinanceChart() {
        var card = document.getElementById("financeChart");
        if (!card) return;
        var items = financeFiltered(state.items || []);
        var year = String(new Date().getFullYear());
        var months = EXP_MONTHS.map(function () { return 0; });
        var today = new Date(); today.setHours(0, 0, 0, 0);
        var dueToday = 0, late = 0, monthSum = 0, daysSum = 0, daysCount = 0;
        var thisMonth = today.getFullYear() + "-" + EXP_MONTHS[today.getMonth()];
        items.forEach(function (it) {
          var f = financeFields(it), st = financeState(it);
          if (f.paid > 0 && f.paidAt) {
            var pd = new Date(f.paidAt);
            if (!isNaN(pd.getTime())) {
              if (String(pd.getFullYear()) === year) months[pd.getMonth()] += f.paid;
              if (String(f.paidAt).slice(0, 7) === thisMonth) monthSum += f.paid;
              if (f.issued) {
                var id = new Date(f.issued);
                if (!isNaN(id.getTime())) {
                  daysSum += Math.max(0, Math.round((pd - id) / 86400000));
                  daysCount++;
                }
              }
            }
          }
          if (st === "collected" || st === "cancelled") return;
          if (it.due_at) {
            var d = new Date(it.due_at);
            if (!isNaN(d.getTime())) {
              if (d.getTime() < today.getTime()) late += f.remain;
              else if (d.toDateString() === today.toDateString()) dueToday += f.remain;
            }
          }
        });
        var debtors = debtorBreakdown(items);
        var donut = donutHtml(debtors, "noDebtorData");
        paintEl(card).html =
          "<h2>" + esc(T("finIndicatorsTitle")) + "</h2>" +
          '<div class="ind-grid">' +
            '<div class="ind-card"><h3>' + esc(T("finMonthlyTitle").replace("{y}", year)) + "</h3>" + monthBarsHtml(months) + "</div>" +
            '<div class="ind-card"><h3>' + esc(T("finTopDebtorsTitle")) + "</h3>" + donut.html + "</div>" +
          "</div>" +
          '<div class="ind-totals">' +
            '<div class="ind-total"><b>' + shortMoney(dueToday) + "</b><span>" + esc(T("finDueToday")) + "</span></div>" +
            '<div class="ind-total"><b>' + shortMoney(late) + "</b><span>" + esc(T("finTotalOverdue")) + "</span></div>" +
            '<div class="ind-total"><b>' + shortMoney(monthSum) + "</b><span>" + esc(T("finCollectedMonth")) + "</span></div>" +
            '<div class="ind-total"><b>' + esc(String(daysCount ? Math.round(daysSum / daysCount) : 0)) + "</b><span>" + esc(T("finAvgDays")) + "</span></div>" +
          "</div>";
      }

      function renderFinance() {
        renderFinanceFilters(state.items);
        renderFinanceMethodSuggest(state.items);
        var items = financeFiltered(state.items).sort(function (a, b) {
          return new Date(b.due_at || 0).getTime() - new Date(a.due_at || 0).getTime();
        });
        renderFinanceTotals(items);
        var body = $("financeBody");
        if (!body) return;
        body.innerHTML = "";
        $("financeWrap").hidden = items.length === 0;
        $("emptyList").hidden = items.length > 0;
        items.forEach(function (item) {
          var f = financeFields(item);
          var st = financeState(item);
          var sk = st === "overdue" ? "overdue" : (st === "collected" ? "done" : (st === "cancelled" ? "cancelled" : "open"));
          var tr = document.createElement("tr");
          tr.innerHTML =
            '<td class="cell-num">' + esc(f.number || "-") +
              '<span class="item-cat">' + esc(finDirLabel(f.dir, true)) + "</span></td>" +
            '<td><span class="item-title" data-tr>' + esc(item.title) + "</span></td>" +
            '<td data-tr>' + esc(f.party || "-") + "</td>" +
            '<td class="cell-num">' + esc(shortDate(f.issued)) + "</td>" +
            '<td class="cell-num">' + (item.due_at
              ? '<div class="cell-stack"><span>' + esc(app.fmtDate(item.due_at)) + '</span>' +
                '<span class="item-cat due-left" data-due="' + esc(item.due_at) + '"' +
                (st === "collected" ? ' data-due-done="1"' : "") + "></span></div>"
              : "-") + "</td>" +
            '<td class="cell-num">' + money(f.base) + "</td>" +
            '<td class="cell-num">' + (f.vat ? money(f.vat) : "-") + "</td>" +
            '<td class="cell-num">' + money(f.total) + "</td>" +
            '<td class="cell-num">' + (f.paid ? money(f.paid) : "-") + "</td>" +
            '<td class="cell-num">' + (f.remain > 0 ? money(f.remain) : "-") + "</td>" +
            '<td><span class="status-' + sk + '">' + esc(T(FIN_STATE_KEYS[st])) + "</span></td>" +
            '<td><div class="chat-options row-actions">' +
              (item.status === "done" ? actionBtn(item, "reopen", "actionReopen") : actionBtn(item, "done", "finActionCollect")) +
              actionBtn(item, "edit", "actionEdit") +
              actionBtn(item, "delete", "actionDelete", "is-danger") +
            "</div></td>";
          body.appendChild(tr);
        });
        translateView();
      }

      (function wireFinanceFilters() {
        var dir = $("financeDirFilter"), st = $("financeStateFilter"), party = $("financePartyFilter");
        if (dir) dir.addEventListener("change", function () { state.financeDir = this.value; renderFinance(); });
        if (st) st.addEventListener("change", function () { state.financeState = this.value; renderFinance(); });
        if (party) party.addEventListener("change", function () { state.financeParty = this.value; renderFinance(); });
      })();

      /* ---------- مصاريف التشغيل: شاشتها لا تشبه القضايا ---------- */
      var EXP_MONTHS = ["01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12"];

      function expenseFields(item) {
        var d = item.due_at || dataOf(item, ["تاريخ الصرف", "التاريخ", "date"]);
        return {
          date: d,
          year: d ? String(new Date(d).getFullYear()) : "",
          month: d ? new Date(d).getMonth() : null,
          cat: item.category || dataOf(item, ["البند", "بند المصروف", "category"]) || T("expNoCat"),
          desc: item.title || "",
          vendor: item.client_name || dataOf(item, ["الجهة", "المورد", "vendor", "supplier"]),
          method: dataOf(item, ["طريقة الدفع", "payment_method", "وسيلة الدفع"]),
          invoice: dataOf(item, ["رقم الفاتورة", "invoice_number"])
        };
      }

      function expenseRows() {
        return (state.items || []).map(function (it) { return { item: it, f: expenseFields(it), amount: Number(it.amount) || 0 }; });
      }

      function expenseFiltered(rows) {
        return rows.filter(function (r) {
          if (state.expenseCat && r.f.cat !== state.expenseCat) return false;
          if (state.expenseYear && r.f.year !== state.expenseYear) return false;
          return true;
        });
      }

      function renderExpenseFilters(rows) {
        var cats = {}, years = {};
        rows.forEach(function (r) { if (r.f.cat) cats[r.f.cat] = true; if (r.f.year) years[r.f.year] = true; });
        var catSel = $("expenseCatFilter"), yearSel = $("expenseYearFilter");
        if (catSel) {
          catSel.innerHTML = '<option value="">' + esc(T("allCats")) + "</option>" +
            Object.keys(cats).sort().map(function (c) {
              return '<option value="' + esc(c) + '"' + (c === state.expenseCat ? " selected" : "") + ">" + esc(c) + "</option>";
            }).join("");
        }
        if (yearSel) {
          yearSel.innerHTML = '<option value="">' + esc(T("allYears")) + "</option>" +
            Object.keys(years).sort().reverse().map(function (y) {
              return '<option value="' + esc(y) + '"' + (y === state.expenseYear ? " selected" : "") + ">" + esc(y) + "</option>";
            }).join("");
        }
      }

      function expenseSums(rows) {
        var now = Date.now(), sum = 0, paid = 0, due = 0, overdue = 0;
        rows.forEach(function (r) {
          sum += r.amount;
          if (r.item.status === "done") paid += r.amount;
          else if (r.item.status !== "cancelled") {
            due += r.amount;
            if (r.f.date && new Date(r.f.date).getTime() < now) overdue += r.amount;
          }
        });
        return { count: rows.length, sum: sum, paid: paid, due: due, overdue: overdue };
      }

      function renderExpenseTotals(rows) {
        var box = $("expenseTotals");
        if (!box) return;
        var t = expenseSums(rows);
        paintEl(box).html =
          '<div class="total-card"><span class="total-label">' + esc(T("expCount")) + '</span><span class="total-value">' + esc(String(t.count)) + "</span></div>" +
          '<div class="total-card"><span class="total-label">' + esc(T("expTotal")) + '</span><span class="total-value">' + money(t.sum) + "</span></div>" +
          '<div class="total-card"><span class="total-label">' + esc(T("expPaid")) + '</span><span class="total-value">' + money(t.paid) + "</span></div>" +
          '<div class="total-card"><span class="total-label">' + esc(T("expDue")) + '</span><span class="total-value">' + money(t.due) + "</span></div>";
      }

      /* أعمدة الأشهر بالمبالغ لا بالعدد: المصروف يقرأ بالريال */
      function monthBarsHtml(values) {
        var max = Math.max.apply(null, values.concat([1]));
        var bars = '<div class="chart-bars">';
        values.forEach(function (v, i) {
          var h = Math.max(4, Math.round((v / max) * 150));
          bars += '<div class="chart-col"><span class="chart-val">' + (v ? shortMoney(v) : "") + "</span>" +
                  '<span class="chart-bar" style="height:' + h + 'px"></span>' +
                  '<span class="chart-label">' + EXP_MONTHS[i] + "</span></div>";
        });
        return bars + "</div>";
      }

      function categoryBreakdown(rows) {
        var sums = {};
        rows.forEach(function (r) { if (r.amount) sums[r.f.cat] = (sums[r.f.cat] || 0) + r.amount; });
        return Object.keys(sums).map(function (k) { return { label: k, value: Math.round(sums[k]) }; })
          .sort(function (a, b) { return b.value - a.value; }).slice(0, 6);
      }

      function renderExpensesChart() {
        var card = document.getElementById("expensesChart");
        if (!card) return;
        var rows = expenseFiltered(expenseRows());
        var year = state.expenseYear || String(new Date().getFullYear());
        var months = EXP_MONTHS.map(function () { return 0; });
        rows.forEach(function (r) {
          if (r.f.month === null || r.f.year !== year) return;
          months[r.f.month] += r.amount;
        });
        var byCat = categoryBreakdown(rows);
        var donut = donutHtml(byCat, "noExpenseData");
        var t = expenseSums(rows);
        var monthsWith = months.filter(function (v) { return v > 0; }).length;
        /* متوسط الشهر من أشهر السنة المعروضة نفسها: قسمة مجموع كل السنوات على
           أشهر سنة واحدة كانت تعطي رقما لا يخص أي سنة. */
        var yearSum = months.reduce(function (a, b) { return a + b; }, 0);

        paintEl(card).html =
          "<h2>" + esc(T("expIndicatorsTitle")) + "</h2>" +
          '<div class="ind-grid">' +
            '<div class="ind-card"><h3>' + esc(T("expMonthlyTitle").replace("{y}", year)) + "</h3>" + monthBarsHtml(months) + "</div>" +
            '<div class="ind-card"><h3>' + esc(T("expByCatTitle").replace("{n}", String(byCat.length))) + "</h3>" + donut.html + "</div>" +
          "</div>" +
          '<div class="ind-totals">' +
            '<div class="ind-total"><b>' + shortMoney(t.sum) + "</b><span>" + esc(T("expTotal")) + "</span></div>" +
            '<div class="ind-total"><b>' + shortMoney(t.due) + "</b><span>" + esc(T("expDue")) + "</span></div>" +
            '<div class="ind-total"><b>' + shortMoney(t.overdue) + "</b><span>" + esc(T("expOverdue")) + "</span></div>" +
            '<div class="ind-total"><b>' + shortMoney(monthsWith ? yearSum / monthsWith : 0) + "</b><span>" + esc(T("expAvgMonth")) + "</span></div>" +
          "</div>";
      }

      function renderExpenses() {
        var all = expenseRows();
        renderExpenseFilters(all);
        var rows = expenseFiltered(all).sort(function (a, b) {
          return new Date(b.f.date || 0).getTime() - new Date(a.f.date || 0).getTime();
        });
        renderExpenseTotals(rows);
        var body = $("expensesBody");
        if (!body) return;
        body.innerHTML = "";
        $("expensesWrap").hidden = rows.length === 0;
        $("emptyList").hidden = rows.length > 0;
        rows.forEach(function (r) {
          var item = r.item, f = r.f, sk = statusKeyOf(item);
          var tr = document.createElement("tr");
          tr.innerHTML =
            '<td class="cell-num">' + esc(shortDate(f.date)) + "</td>" +
            "<td>" + esc(f.cat || "-") + "</td>" +
            '<td><span class="item-title">' + esc(f.desc || "-") + "</span>" +
              (f.invoice ? '<span class="item-cat">' + esc(f.invoice) + "</span>" : "") + "</td>" +
            "<td>" + esc(f.vendor || "-") + "</td>" +
            '<td class="cell-num">' + money(item.amount) + "</td>" +
            "<td>" + esc(f.method || "-") + "</td>" +
            '<td><span class="status-' + sk + '">' + esc(T(sk === "done" ? "expStatusPaid" : STATUS_KEYS[sk])) + "</span></td>" +
            '<td><div class="chat-options row-actions">' +
              (item.status === "done" ? actionBtn(item, "reopen", "actionReopen") : actionBtn(item, "done", "expActionPay")) +
              actionBtn(item, "edit", "actionEdit") +
              actionBtn(item, "delete", "actionDelete", "is-danger") +
            "</div></td>";
          body.appendChild(tr);
        });
      }

      function renderViolations() {
        var items = state.items.filter(function (it) {
          if (!state.clientFilter) return true;
          var shown = (app.clientDisplayName ? app.clientDisplayName(it) : it.client_name) || "";
          return shown === state.clientFilter || it.client_name === state.clientFilter || it.client_name_en === state.clientFilter;
        });
        renderClientFilter(state.items);
        renderTotals(items);
        var body = $("violationsBody");
        body.innerHTML = "";
        $("violationsWrap").hidden = items.length === 0;
        $("emptyList").hidden = items.length > 0;
        items.forEach(function (item) {
          var f = violationFields(item);
          var sk = statusKeyOf(item);
          var tr = document.createElement("tr");
          tr.innerHTML =
            '<td class="cell-num">' + esc(f.number || "-") + "</td>" +
            '<td class="cell-num">' + esc(shortDate(f.date)) + "</td>" +
            '<td data-tr>' + esc(f.client || "-") + "</td>" +
            "<td>" + esc(f.issuer || "-") + "</td>" +
            '<td class="cell-num">' + money(item.amount) + "</td>" +
            "<td>" + esc(f.vtype || "-") + "</td>" +
            "<td>" + esc(f.objection || "-") + "</td>" +
            '<td class="cell-num">' + (f.caseNumber
              ? '<a href="#" class="case-link" data-case="' + esc(f.caseNumber) + '">' + esc(f.caseNumber) + "</a>"
              : "-") + "</td>" +
            '<td class="cell-num">' + (item.due_at ? esc(app.fmtDate(item.due_at)) : "-") + "</td>" +
            '<td><span class="status-' + sk + '">' + esc(T(STATUS_KEYS[sk])) + "</span></td>" +
            '<td><div class="chat-options row-actions">' +
              (item.status === "done" ? actionBtn(item, "reopen", "actionReopen") : actionBtn(item, "done", "actionDone")) +
              actionBtn(item, "edit", "actionEdit") +
              actionBtn(item, "delete", "actionDelete", "is-danger") +
            "</div></td>";
          body.appendChild(tr);
        });
      }

      /* رقم الدعوى يجمع المخالفة وقضيتها وملفاتهما */
      /* أنواع أبناء القضية بترتيب قراءتها في الملف */
      var CASE_SECTIONS = [
        { kind: "session",   key: "secSessions" },
        { kind: "ruling",    key: "secRulings" },
        { kind: "execution", key: "secExecutions" },
        { kind: "violation", key: "secViolations" },
        { kind: "task",      key: "secTasks" },
        { kind: "document",  key: "secDocuments" }
      ];

      function caseRowsHtml(rows) {
        var html = '<div class="table-wrap"><table class="items-table"><thead><tr>' +
          "<th>" + esc(T("colTitle")) + "</th><th>" + esc(T("colDue")) + "</th>" +
          "<th>" + esc(T("colAmount")) + "</th><th>" + esc(T("colStatus")) + "</th>" +
          "<th>" + esc(T("attachTitle")) + "</th><th></th></tr></thead><tbody>";
        rows.forEach(function (r) {
          var next = r.kind === "session"
            ? '<button type="button" class="chat-option-btn" data-next-session="' + esc(r.id) + '">' + esc(T("nextSession")) + "</button>"
            : (r.kind === "ruling"
              ? '<button type="button" class="chat-option-btn" data-appeal="' + esc(r.id) + '">' + esc(T("appealDeadline")) + "</button>"
              : "");
          html += "<tr><td>" + esc(r.title || "-") + "</td>" +
                  '<td class="cell-num">' + (r.due_at ? esc(app.fmtDate(r.due_at)) : "-") + "</td>" +
                  '<td class="cell-num">' + money(r.amount) + "</td>" +
                  "<td>" + esc(r.status === "done" ? T("statusDone") : T("statusOpen")) + "</td>" +
                  '<td class="cell-num">' + esc(String(r.attachments || 0)) + "</td>" +
                  '<td><div class="chat-options row-actions">' + next +
                    '<button type="button" class="chat-option-btn" data-bundle-open="' + esc(r.id) + '">' + esc(T("actionEdit")) + "</button></div></td></tr>";
        });
        return html + "</tbody></table></div>";
      }

      /* الجلسة القادمة تكتب من الجلسة الحالية: النموذج نفسه مملوءا من القضية،
         والعنصر الجديد يربط بالقضية نفسها فلا يطفو وحده. */
      function startNextSession(sessionId) {
        var head = state.caseHead;
        var kids = state.caseKids || [];
        var session = kids.filter(function (k) { return k.id === sessionId; })[0];
        if (!head) return;
        var panel = $("addItemPanel");
        panel.hidden = false;
        clearMsg("addMsg");
        closeEdit();
        state.pendingParent = head.id;
        $("addTitle").value = T("nextSessionTitle").replace("{case}", head.title || "");
        $("addCategory").value = (session && session.category) || T("sessionCategory");
        $("addClient").value = head.client_name || "";
        $("addClientEn").value = head.client_name_en || "";
        $("addCaseNumber").value = head.case_number || "";
        $("addAmount").value = "";
        $("addDue").value = "";
        if ($("addRecord") && head.record_id) $("addRecord").value = head.record_id;
        try { panel.scrollIntoView({ behavior: "smooth", block: "center" }); } catch (e) { /* تجاهل */ }
        /* حقل التاريخ صار منتقيا: المؤشر يذهب إلى الحقل الظاهر لا إلى حقل المتصفح المخفي */
        var due = $("addDue");
        var wrap = due && due.closest ? due.closest(".dp-wrap, .date-field") : null;
        var shown = wrap ? wrap.querySelector('input[type="text"]') : null;
        (shown || due).focus();
      }

      /* مهلة الاستئناف: موعد يكتب على القضية نفسها وينبه قبله.
         مدة المهلة لا تفترض هنا — المحامي يكتب التاريخ لأنها تختلف
         باختلاف المحكمة ونوع الحكم. */
      function startAppealDeadline(rulingId) {
        var head = state.caseHead;
        var ruling = (state.caseKids || []).filter(function (k) { return k.id === rulingId; })[0];
        if (!head) return;
        var panel = $("addItemPanel");
        panel.hidden = false;
        clearMsg("addMsg");
        closeEdit();
        state.pendingParent = head.id;
        $("addTitle").value = T("appealTitle").replace("{case}", (ruling && ruling.title) || head.title || "");
        $("addCategory").value = T("appealCategory");
        $("addClient").value = head.client_name || "";
        $("addClientEn").value = head.client_name_en || "";
        $("addCaseNumber").value = head.case_number || "";
        $("addAmount").value = "";
        $("addDue").value = "";
        if ($("addRecord") && head.record_id) $("addRecord").value = head.record_id;
        try { panel.scrollIntoView({ behavior: "smooth", block: "center" }); } catch (e) { /* تجاهل */ }
        var due = $("addDue");
        var wrap = due && due.closest ? due.closest(".dp-wrap, .date-field") : null;
        var shown = wrap ? wrap.querySelector('input[type="text"]') : null;
        (shown || due).focus();
      }

      /* ملف القضية الكامل: يفتح من رقم القضية أو من صفها */
      function openCaseFile(itemId) {
        var box = $("caseBundle");
        if (!box || !app.client) return;
        app.client.rpc("case_file", { p_org: app.org.id, p_case: itemId }).then(function (res) {
          var data = res && res.data;
          if (!data || data.error || !data.head) { paintEl(box).html = '<p class="empty-note">' + esc(T("caseBundleEmpty")) + "</p>"; return; }
          var head = data.head, kids = data.children || [];
          state.caseHead = head; state.caseKids = kids;
          var d = head.data || {};
          var facts = [
            [T("colCaseNumber"), head.case_number],
            [T("fieldClient"), head.client_name],
            [T("fieldCourt"), d.court],
            [T("fieldStage"), head.stage],
            [T("colAmount"), head.amount != null ? money(head.amount) : null]
          ].filter(function (f) { return f[1]; });
          var html = "<h3>" + esc(head.title || T("caseFileTitle")) + "</h3>" +
            '<div class="totals-row">' + facts.map(function (f) {
              return '<div class="total-card"><span class="total-label">' + esc(f[0]) + '</span><span class="total-value">' + f[1] + "</span></div>";
            }).join("") + "</div>";
          CASE_SECTIONS.forEach(function (sec) {
            var rows = kids.filter(function (k) { return k.kind === sec.kind; });
            if (!rows.length) return;
            html += "<h4>" + esc(T(sec.key)) + " (" + rows.length + ")</h4>" + caseRowsHtml(rows);
          });
          if (!kids.length) html += '<p class="empty-note">' + esc(T("caseFileEmpty")) + "</p>";
          paintEl(box).html = html;
          try { box.scrollIntoView({ behavior: "smooth", block: "nearest" }); } catch (e) { /* تجاهل */ }
        }).catch(function () {
          paintEl(box).html = '<p class="empty-note">' + esc(T("caseBundleEmpty")) + "</p>";
        });
      }

      function openCaseBundle(caseNumber) {
        var box = $("caseBundle");
        if (!box) return;
        app.caseBundle(caseNumber).then(function (rows) {
          var list = rows || [];
          if (!list.length) {
            paintEl(box).html = "<h3>" + esc(T("caseBundleTitle").replace("{n}", caseNumber)) + '</h3><p class="empty-note">' + esc(T("caseBundleEmpty")) + "</p>";
            return;
          }
          var html = "<h3>" + esc(T("caseBundleTitle").replace("{n}", caseNumber)) + "</h3>" +
            '<div class="table-wrap">' +
            "<table><thead><tr>" +
            "<th>" + esc(T("colTitle")) + "</th><th>" + esc(T("fieldCategory")) + "</th>" +
            "<th>" + esc(T("colDue")) + "</th><th>" + esc(T("colAmount")) + "</th>" +
            "<th>" + esc(T("attachTitle")) + "</th><th></th></tr></thead><tbody>";
          list.forEach(function (r) {
            html += "<tr><td>" + esc(r.title || "-") + "</td>" +
                    "<td>" + esc(r.category || "-") + "</td>" +
                    '<td class="cell-num">' + (r.due_at ? esc(app.fmtDate(r.due_at)) : "-") + "</td>" +
                    '<td class="cell-num">' + money(r.amount) + "</td>" +
                    '<td class="cell-num">' + esc(String(r.attachments || 0)) + "</td>" +
                    '<td><button type="button" class="chat-option-btn" data-bundle-open="' + esc(r.item_id) + '">' + esc(T("actionEdit")) + "</button></td></tr>";
          });
          html += "</tbody></table></div>";
          paintEl(box).html = html;
        }).catch(function () {
          paintEl(box).html = "<h3>" + esc(T("caseBundleTitle").replace("{n}", caseNumber)) + '</h3><p class="empty-note">' + esc(T("caseBundleEmpty")) + "</p>";
        });
      }

      document.addEventListener("click", function (ev) {
        var link = ev.target.closest(".case-link");
        if (link) {
          ev.preventDefault();
          openCaseBundle(link.dataset.case);
          return;
        }
        var fileBtn = ev.target.closest("[data-case-file]");
        if (fileBtn) { ev.preventDefault(); openCaseFile(fileBtn.dataset.caseFile); return; }
        var nextBtn = ev.target.closest("[data-next-session]");
        if (nextBtn) { ev.preventDefault(); startNextSession(nextBtn.dataset.nextSession); return; }
        var appealBtn = ev.target.closest("[data-appeal]");
        if (appealBtn) { ev.preventDefault(); startAppealDeadline(appealBtn.dataset.appeal); return; }
        var openBtn = ev.target.closest("[data-bundle-open]");
        if (openBtn) {
          var id = openBtn.dataset.bundleOpen;
          var item = (state.items || []).filter(function (it) { return it.id === id; })[0];
          if (item) openEdit(item);
        }
      });

      function translateView() {
        if (!app.translateNodes) return;
        var root = document.getElementById("dashboard");
        if (root) app.translateNodes(root);
      }

      /* التصنيف يقترح ما استعمله المستخدم فعلا في عناصره، ويبقى قابلا للكتابة الحرة */
      var lastCatHtml = "";
      function renderCategorySuggest() {
        var box = document.getElementById("categorySuggest");
        if (!box) return;
        var seen = {}, list = [];
        (state.items || []).forEach(function (it) {
          var c = String(it.category || "").trim();
          if (!c || seen[c]) return;
          seen[c] = true; list.push(c);
        });
        list.sort();
        var html = list.map(function (c) { return '<option value="' + esc(c) + '"></option>'; }).join("");
        if (html === lastCatHtml) return;
        lastCatHtml = html;
        box.innerHTML = html;
      }

      /* ــ جدول القائمة بحسب الحزمة ــ
         الخلايا من مفردات مغلقة في الشيفرة، والحزمة تختار أيها يظهر وبأي عنوان.
         بلا إعلان يعود الجدول إلى أعمدته الستة كما هي اليوم. */
      function packColumns() {
        var cfg = app.packCfg ? app.packCfg("list_columns") : null;
        var list = cfg && (cfg[state.viewType || "default"] || cfg.default);
        return Array.isArray(list) && list.length ? list : null;
      }

      function cellHtml(cell, item) {
        var sk = statusKeyOf(item);
        switch (cell) {
          case "title+category":
            return '<td><span class="item-title" data-tr>' + esc(item.title) + "</span>" +
                   (item.category ? '<span class="item-cat">' + esc(item.category) + "</span>" : "") + "</td>";
          case "title": return '<td><span class="item-title" data-tr>' + esc(item.title) + "</span></td>";
          case "record": return "<td>" + esc(recordName(item)) + "</td>";
          case "due": return '<td class="col-due">' + (item.due_at ? esc(app.fmtDate(item.due_at, { withTime: true })) : esc(T("noDue"))) + "</td>";
          case "due+left":
            return '<td class="col-due">' + (item.due_at
              ? '<div class="cell-stack"><span>' + esc(app.fmtDate(item.due_at, { withTime: true })) + '</span><span class="item-cat due-left" data-due="' + esc(item.due_at) + '"></span></div>'
              : esc(T("noDue"))) + "</td>";
          case "assignee": return "<td>" + esc(assigneeName(item.assignee_id)) + "</td>";
          case "status": return '<td><span class="status-' + sk + '">' + esc(T(STATUS_KEYS[sk])) + "</span></td>";
          case "amount": return '<td class="cell-num">' + (item.amount == null ? "-" : money(item.amount)) + "</td>";
          case "client": return "<td>" + esc(item.client_name || "-") + "</td>";
          case "case_number": return '<td dir="ltr">' + esc(item.case_number || "-") + "</td>";
          case "category": return "<td>" + esc(item.category || "-") + "</td>";
          case "actions":
            return '<td><div class="chat-options row-actions">' +
              (item.status === "done" ? actionBtn(item, "reopen", "actionReopen") : actionBtn(item, "done", "actionDone")) +
              actionBtn(item, "edit", "actionEdit") +
              actionBtn(item, "delete", "actionDelete", "is-danger") + "</div></td>";
          default: return "<td>-</td>";
        }
      }

      var lastHeadSig = "";
      function renderPackTable() {
        var cols = packColumns();
        if (!cols) return false;
        var head = $("itemsHead"), body = $("itemsBody");
        if (!head || !body) return false;
        var sig = cols.map(function (c) { return c.cell + ":" + ((c.label && (c.label[l] || c.label.ar)) || ""); }).join("|") + "|" + l;
        if (sig !== lastHeadSig) {
          lastHeadSig = sig;
          head.innerHTML = "<tr>" + cols.map(function (c) {
            return "<th>" + esc((c.label && (c.label[l] || c.label.ar)) || "") + "</th>";
          }).join("") + "</tr>";
        }
        var items = state.items;
        $("emptyList").hidden = items.length > 0;
        $("tableWrap").hidden = items.length === 0;
        body.innerHTML = items.map(function (item) {
          return "<tr>" + cols.map(function (c) { return cellHtml(c.cell, item); }).join("") + "</tr>";
        }).join("");
        translateView();
        return true;
      }

      function renderList() {
        renderCategorySuggest();
        renderWeek();
        renderChart();
        renderCasesChart();
        renderOwnChart();      /* مؤشر الواجهة التي لا قضايا فيها */
        renderExpensesChart();
        renderFinanceChart();
        if (state.viewType === "violations") {
          $("violationsBar").hidden = false;
          $("tableWrap").hidden = true;
          $("expensesBar").hidden = true;
          $("expensesWrap").hidden = true;
          $("contractsBar").hidden = true;
          $("contractsWrap").hidden = true;
          $("financeBar").hidden = true;
          $("financeWrap").hidden = true;
          renderViolations();
          return;
        }
        if (state.viewType === "expenses") {
          $("expensesBar").hidden = false;
          $("tableWrap").hidden = true;
          $("violationsBar").hidden = true;
          $("violationsWrap").hidden = true;
          $("contractsBar").hidden = true;
          $("contractsWrap").hidden = true;
          $("healthBar").hidden = true;
          $("healthWrap").hidden = true;
          $("financeBar").hidden = true;
          $("financeWrap").hidden = true;
          renderExpenses();
          return;
        }
        if (state.viewType === "contracts") {
          $("contractsBar").hidden = false;
          $("tableWrap").hidden = true;
          $("violationsBar").hidden = true;
          $("violationsWrap").hidden = true;
          $("expensesBar").hidden = true;
          $("expensesWrap").hidden = true;
          $("healthBar").hidden = true;
          $("healthWrap").hidden = true;
          $("financeBar").hidden = true;
          $("financeWrap").hidden = true;
          renderContracts();
          return;
        }
        if (state.viewType === "health") {
          $("healthBar").hidden = false;
          $("tableWrap").hidden = true;
          $("violationsBar").hidden = true;
          $("violationsWrap").hidden = true;
          $("expensesBar").hidden = true;
          $("expensesWrap").hidden = true;
          $("contractsBar").hidden = true;
          $("contractsWrap").hidden = true;
          $("financeBar").hidden = true;
          $("financeWrap").hidden = true;
          renderHealth();
          return;
        }
        if (state.viewType === "invoices") {
          $("financeBar").hidden = false;
          $("tableWrap").hidden = true;
          $("violationsBar").hidden = true;
          $("violationsWrap").hidden = true;
          $("expensesBar").hidden = true;
          $("expensesWrap").hidden = true;
          $("contractsBar").hidden = true;
          $("contractsWrap").hidden = true;
          $("healthBar").hidden = true;
          $("healthWrap").hidden = true;
          renderFinance();
          return;
        }
        $("expensesBar").hidden = true;
        $("expensesWrap").hidden = true;
        $("violationsBar").hidden = true;
        $("violationsWrap").hidden = true;
        $("contractsBar").hidden = true;
        $("contractsWrap").hidden = true;
        $("healthBar").hidden = true;
        $("healthWrap").hidden = true;
        $("financeBar").hidden = true;
        $("financeWrap").hidden = true;
        if (renderPackTable()) return;
        var body = $("itemsBody");
        body.innerHTML = "";
        var items = state.items;
        $("emptyList").hidden = items.length > 0;
        $("tableWrap").hidden = items.length === 0;
        /* القائمة قسمان بامره: قادمة وسابقة. السابق ما مضى موعده بمكتمله وغير مكتمله،
           وصفوفه تحمل زر اعادة الجدولة. وما لا موعد له لم يمض، فهو في القادمة. */
        var nowMs = Date.now();
        var past = items.filter(function (it) { return it.due_at && new Date(it.due_at).getTime() < nowMs; });
        var upcoming = items.filter(function (it) { return !(it.due_at && new Date(it.due_at).getTime() < nowMs); });
        var groupRow = function (label, count) {
          var row = document.createElement("tr");
          row.className = "list-group";
          row.innerHTML = '<td colspan="6"><span class="list-group-name">' + esc(label) + "</span>" +
                          '<span class="list-group-count">' + count + "</span></td>";
          return row;
        };
        var render = function (item) {
          var sk = statusKeyOf(item);
          var tr = document.createElement("tr");
          tr.innerHTML =
            '<td><span class="item-title" data-tr>' + esc(item.title) + "</span>" +
              (item.category ? '<span class="item-cat">' + esc(item.category) + "</span>" : "") + "</td>" +
            "<td>" + esc(recordName(item)) + "</td>" +
            '<td class="col-due">' + (item.due_at
              ? '<div class="cell-stack"><span>' + esc(app.fmtDate(item.due_at, { withTime: true })) + '</span><span class="item-cat due-left" data-due="' + esc(item.due_at) + '"' + (item.status === "done" ? ' data-due-done="1"' : "") + '></span></div>'
              : esc(T("noDue"))) + "</td>" +
            "<td>" + esc(assigneeName(item.assignee_id)) + "</td>" +
            '<td><span class="status-' + sk + '">' + esc(T(STATUS_KEYS[sk])) + "</span></td>" +
            '<td><div class="chat-options row-actions">' +
              (state.viewType === "cases"
                ? '<button type="button" class="chat-option-btn is-icon" data-case-file="' + esc(item.id) + '" title="' + esc(T("openCaseFile")) + '" aria-label="' + esc(T("openCaseFile")) + '">' +
                  '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M10 4H4a2 2 0 00-2 2v12a2 2 0 002 2h16a2 2 0 002-2V8a2 2 0 00-2-2h-8l-2-2z"/></svg></button>'
                : "") +
              (item.due_at && new Date(item.due_at).getTime() < nowMs ? actionBtn(item, "reschedule", "actionReschedule") : "") +
              (item.status === "done" ? actionBtn(item, "reopen", "actionReopen") : actionBtn(item, "done", "actionDone")) +
              actionBtn(item, "edit", "actionEdit") +
              actionBtn(item, "delete", "actionDelete", "is-danger") +
            "</div></td>";
          body.appendChild(tr);
        };
        if (upcoming.length) { body.appendChild(groupRow(T("listUpcoming"), upcoming.length)); upcoming.forEach(render); }
        if (past.length) { body.appendChild(groupRow(T("listPast"), past.length)); past.forEach(render); }
        translateView();
      }

      /* جدولا القائمة والمخالفات يتشاركان الأزرار نفسها، فالمستمع على المستند */
      document.addEventListener("click", function (ev) {
        var b = ev.target.closest("button[data-action]");
        if (!b || !b.closest("#itemsBody, #violationsBody, #contractsBody, #expensesBody")) return;
        var item = findItem(b.dataset.id);
        if (!item) return;
        var action = b.dataset.action;
        if (action === "done") setItemStatus(item, "done", "itemDone");
        else if (action === "reopen") setItemStatus(item, "open", "itemReopened");
        else if (action === "edit") openEdit(item);
        else if (action === "reschedule") {
          /* اعادة الجدولة: النموذج نفسه، والمؤشر في حقل الموعد مباشرة */
          openEdit(item);
          var due = $("editDue");
          var wrap = due && due.closest ? due.closest(".dp-wrap, .date-field") : null;
          var shown = wrap ? wrap.querySelector('input[type="text"]') : null;
          if (shown || due) (shown || due).focus();
        }
        else if (action === "delete") deleteItem(item);
      });

      function setItemStatus(item, status, key) {
        guard(function () {
          return app.updateItem(item.id, { status: status }).then(function () {
            toast(key);
            return refresh();
          });
        }).catch(function (err) { fail(err, "listMsg"); });
      }

      function deleteItem(item) {
        if (!window.confirm(T("confirmDelete"))) return;
        guard(function () {
          return app.deleteItem(item.id).then(function () {
            if (state.editing && state.editing.id === item.id) closeEdit();
            toast("deleted");
            return refresh();
          });
        }).catch(function (err) { fail(err, "listMsg"); });
      }

      /* ---------- add item / new record ---------- */

      $("addItemBtn").addEventListener("click", function () {
        if (state.viewType && VIEW_TYPES[state.viewType]) {
          var catField = $("addCategory");
          if (catField && !catField.value) catField.value = VIEW_TYPES[state.viewType].defaultCategory;
        }
        applyViewFields();
        if (state.viewType === "contracts") fillRenewalOptions($("addContractRenewal"), $("addContractRenewal").value);
        if (state.viewType === "health") { fillHealthOptions("add"); ensureHealthRecord(); }
        if (state.viewType === "invoices") fillFinanceOptions("add");
        if (state.viewType === "deals") fillDealOptions("add");
        var p = $("addItemPanel");
        p.hidden = !p.hidden;
        clearMsg("addMsg");
        if (!p.hidden) { closeEdit(); $("addTitle").focus(); }
      });
      $("addCancelBtn").addEventListener("click", function () { hide("addItemPanel"); clearMsg("addMsg"); });

      $("addItemForm").addEventListener("submit", function (ev) {
        ev.preventDefault();
        var title = $("addTitle").value.trim();
        if (!title) { setMsg("addMsg", T("titleRequired"), "error"); $("addTitle").focus(); return; }
        var recordId = $("addRecord").value;
        if (!recordId) { setMsg("addMsg", T("recordRequired"), "error"); $("addRecord").focus(); return; }
        clearMsg("addMsg");
        var row = {
          record_id: recordId,
          title: title,
          due_at: fromLocalInput($("addDue").value),
          category: $("addCategory").value.trim() || null,
          assignee_id: $("addAssignee").value || null,
          amount: numOrNull($("addAmount").value),
          client_name: $("addClient").value.trim() || null,
          client_name_en: $("addClientEn").value.trim() || null,
          case_number: $("addCaseNumber").value.trim() || null,
          status: "open"
        };
        var cdata = contractRowData("add");
        if (cdata) row.data = cdata;
        var ddata = dealRowData("add");
        if (ddata) row.data = Object.assign({}, row.data || {}, ddata);
        var hdata = healthRowData("add");
        if (hdata) {
          row.data = Object.assign({}, row.data || {}, hdata);
          if (!row.category) row.category = healthCategoryFor("add");
        }
        var fdata = financeRowData("add");
        if (fdata) {
          row.data = Object.assign({}, row.data || {}, fdata);
          row.amount = fdata.total_sar || null;   /* الاجمالي شامل الضريبة هو مبلغ العنصر */
          if (!row.category) row.category = financeCategoryFor("add");
        }
        if (state.pendingParent) row.parent_id = state.pendingParent;
        guard(function () {
          $("addSaveBtn").disabled = true;
          return app.insertItems([row]).then(function () {
            toast("itemAdded");
            $("addTitle").value = "";
            $("addDue").value = "";
            $("addCategory").value = "";
            $("addAmount").value = "";
            $("addClient").value = "";
            $("addClientEn").value = "";
            $("addCaseNumber").value = "";
            clearContractFields("add");
            clearHealthFields("add");
            clearFinanceFields("add");
            state.pendingParent = "";
            return refresh();
          });
        }).then(function () { $("addSaveBtn").disabled = false; }, function (err) {
          $("addSaveBtn").disabled = false;
          fail(err, "addMsg");
        });
      });

      $("newRecordBtn").addEventListener("click", function () {
        var f = $("newRecordForm");
        f.hidden = !f.hidden;
        clearMsg("newRecordMsg");
        if (!f.hidden) $("newRecordName").focus();
      });
      $("newRecordCancel").addEventListener("click", function () { hide("newRecordForm"); clearMsg("newRecordMsg"); });
      $("newRecordForm").addEventListener("submit", function (ev) {
        ev.preventDefault();
        var name = $("newRecordName").value.trim();
        if (!name) { setMsg("newRecordMsg", T("recordNameRequired"), "error"); return; }
        clearMsg("newRecordMsg");
        guard(function () {
          return app.createRecord({ name: name }).then(function (t) {
            state.records.push(t);
            renderSelects();
            $("addRecord").value = t.id;
            $("newRecordName").value = "";
            hide("newRecordForm");
            toast("recordCreated");
          });
        }).catch(function (err) { fail(err, "newRecordMsg"); });
      });

      /* ---------- ملخص الأسبوع ----------
         ثلاثة أرقام من العناصر نفسها: ما أنجز، وما أضيف، وما تأخر،
         وتحت كل رقم مقارنته بالأسبوع الماضي. بنمط بطاقات المؤشرات نفسه. */
      function weekStart(offsetWeeks) {
        var d = new Date();
        d.setHours(0, 0, 0, 0);
        d.setDate(d.getDate() - d.getDay() + (offsetWeeks || 0) * 7);   /* الأسبوع يبدأ الأحد */
        return d;
      }

      function inRange(iso, from, to) {
        if (!iso) return false;
        var t = new Date(iso).getTime();
        return isFinite(t) && t >= from.getTime() && t < to.getTime();
      }

      function weekCounts(items, from, to) {
        var out = { done: 0, added: 0, late: 0 };
        (items || []).forEach(function (it) {
          if (it.status === "done" && inRange(it.updated_at, from, to)) out.done += 1;
          if (inRange(it.created_at, from, to)) out.added += 1;
          if (it.status !== "done" && it.status !== "cancelled" && inRange(it.due_at, from, to) &&
              new Date(it.due_at).getTime() < Date.now()) out.late += 1;
        });
        return out;
      }

      /* لا سالب في ملخص الاسبوع (امر المهندس رعد 2026-09-14: «مافي شي اسمو سالب
         في الاضافات، خليه يعرض صفر فقط او الزيادات»): الزيادة تعلن بعلامتها،
         والتساوي يقال كما كان، وما دونهما يترك السطر فارغا فلا يعرض نقصا.
         والسطر يبقى موجودا محجوزا بمسافة غير فاصلة كي تتساوى ارتفاعات البطاقات
         الثلاث مهما اختلفت ارقامها. */
      function trendText(now, before) {
        var diff = now - before;
        if (diff > 0) return "+" + diff + " " + T("weekVsLast");
        if (diff === 0) return T("weekSame");
        return "";
      }

      /* الأرقام من القاعدة على كل العناصر لا على الصفحة المحملة (500 صف).
         إن تعذرت الدالة تحسب محليا كما كانت، فلا تختفي البطاقة أبدا. */
      function loadWeek() {
        if (!app.client || !app.org) return Promise.resolve(null);
        return app.client.rpc("week_summary", { p_org: app.org.id }).then(function (res) {
          var row = res && res.data;
          if (Array.isArray(row)) row = row[0];
          state.week = (row && typeof row.done_this_week === "number") ? row : null;
          return state.week;
        }).catch(function () { state.week = null; return null; });
      }

      function renderWeek() {
        var card = $("weekCard");
        if (!card) return;
        var items = state.items || [];
        var thisFrom = weekStart(0), nextFrom = new Date(thisFrom.getTime() + 7 * 86400000);
        var lastFrom = weekStart(-1);
        var w = state.week;
        var now = w ? { done: w.done_this_week, added: w.added_this_week, late: w.late_this_week }
                    : weekCounts(items, thisFrom, nextFrom);
        var before = w ? { done: w.done_last_week, added: w.added_last_week, late: w.late_last_week }
                       : weekCounts(items, lastFrom, thisFrom);
        var boxes = [
          { key: "weekDone", n: now.done, was: before.done, cls: "status-done" },
          { key: "weekAdded", n: now.added, was: before.added, cls: "" },
          { key: "weekLate", n: now.late, was: before.late, cls: now.late ? "status-overdue" : "" }
        ];
        var html = "<h3>" + esc(T("weekTitle")) + "</h3>" +
          '<div class="totals-row">' + boxes.map(function (b) {
            return '<div class="total-card"><span class="total-label">' + esc(T(b.key)) + "</span>" +
                   '<span class="total-value ' + b.cls + '">' + b.n + "</span>" +
                   '<span class="total-label">' + (esc(trendText(b.n, b.was)) || "&nbsp;") + "</span></div>";
          }).join("") + "</div>";
        paintEl(card).html = html;
        card.hidden = false;
      }

      /* ---------- التذكير قبل الموعد ---------- */
      /* القيم كما تكتبها القاعدة في items.remind_before، وnull يعني القاعدة العامة للسجل */
      var REMIND_CHOICES = ["", "1 day", "3 days", "7 days", "14 days", "30 days"];
      var REMIND_KEYS = { "": "remindDefault", "1 day": "remindDay", "3 days": "remind3Days",
                          "7 days": "remindWeek", "14 days": "remind2Weeks", "30 days": "remindMonth" };

      /* القاعدة تعيد المدة نصا مثل "7 days" أو "1 day" أو "7 days 00:00:00" */
      function remindValue(raw) {
        var v = String(raw == null ? "" : raw).trim();
        if (!v) return "";
        var m = v.match(/(\d+)\s*(day|days|mon|mons|month|months|week|weeks)/i);
        if (!m) return "";
        var n = Number(m[1]);
        var unit = m[2].toLowerCase();
        if (unit.indexOf("week") === 0) n *= 7;
        if (unit.indexOf("mon") === 0) n *= 30;
        var text = n === 1 ? "1 day" : n + " days";
        return REMIND_CHOICES.indexOf(text) === -1 ? "" : text;
      }

      function fillRemindOptions(sel, current) {
        if (!sel) return;
        sel.innerHTML = REMIND_CHOICES.map(function (v) {
          return '<option value="' + v + '">' + esc(T(REMIND_KEYS[v])) + "</option>";
        }).join("");
        sel.value = remindValue(current);
      }

      /* ---------- inline edit ---------- */

      function openEdit(item) {
        state.editing = item;
        hide("addItemPanel");
        $("editTitle").value = item.title || "";
        $("editRecord").value = item.record_id || "";
        $("editDue").value = toLocalInput(item.due_at);
        $("editCategory").value = item.category || "";
        $("editAssignee").value = item.assignee_id || "";
        $("editStatus").value = STATUS_KEYS[item.status] && item.status !== "overdue" ? item.status : "open";
        $("editAmount").value = item.amount != null ? item.amount : "";
        $("editClient").value = item.client_name || "";
        $("editClientEn").value = item.client_name_en || "";
        $("editCaseNumber").value = item.case_number || "";
        applyViewFields();
        if (state.viewType === "contracts") fillContractFields("edit", item);
        if (state.viewType === "health") fillHealthFields("edit", item);
        if (state.viewType === "invoices") fillFinanceFields("edit", item);
        if (state.viewType === "deals") fillDealFields("edit", item);
        fillRemindOptions($("editRemind"), item.remind_before);
        clearMsg("editMsg");
        show("editPanel");
        loadAttachments();
        try { $("editPanel").scrollIntoView({ behavior: "smooth", block: "nearest" }); } catch (e) { /* ignore */ }
        $("editTitle").focus();
      }

      /* ---------- المرفقات ---------- */

      function humanSize(bytes) {
        var n = Number(bytes) || 0;
        if (n < 1024) return n + " B";
        if (n < 1048576) return (n / 1024).toFixed(0) + " KB";
        return (n / 1048576).toFixed(1) + " MB";
      }

      function renderAttachments(rows) {
        var box = $("attachList");
        if (!box) return;
        if (!rows || !rows.length) { paintEl(box).html = '<p class="empty-note">' + esc(T("attachEmpty")) + "</p>"; return; }
        var html = "";
        rows.forEach(function (a) {
          html += '<div class="attach-row"><a href="#" data-attach-open="' + esc(a.id) + '">' + esc(a.name) + "</a>" +
                  "<span>" + esc(a.external_url ? T("attachLinkLabel") : humanSize(a.size_bytes)) + "</span>" +
                  '<button type="button" class="chat-option-btn" data-attach-del="' + esc(a.id) + '">' + esc(T("delete")) + "</button></div>";
        });
        paintEl(box).html = html;
      }

      function loadAttachments() {
        if (!state.editing) return Promise.resolve();
        return app.listAttachments(state.editing.id).then(function (rows) {
          state.attachments = rows || [];
          renderAttachments(state.attachments);
        }).catch(function () { renderAttachments([]); });
      }

      function attachById(id) {
        return (state.attachments || []).filter(function (a) { return a.id === id; })[0] || null;
      }

      function wireAttachments() {
        var fileInput = $("attachFile");
        if (fileInput) fileInput.addEventListener("change", function () {
          var file = this.files && this.files[0];
          if (!file || !state.editing) return;
          setMsg("attachMsg", T("attachUploading"));
          app.uploadAttachment(state.editing.id, file).then(function () {
            setMsg("attachMsg", T("attachDone"), "success");
            return loadAttachments();
          }).catch(function (err) {
            var code = String((err && (err.message || err.code)) || "");
            setMsg("attachMsg", code.indexOf("PLAN_LIMIT_STORAGE") !== -1 ? T("attachLimit") : T("attachFailed"), "error");
          }).finally(function () { fileInput.value = ""; });
        });

        var driveBtn = $("attachDriveBtn");
        function syncDriveBtn() { if (driveBtn) driveBtn.hidden = !(app.driveAvailable && app.driveAvailable()); }
        syncDriveBtn();
        document.addEventListener("record:drive", syncDriveBtn);
        if (driveBtn) driveBtn.addEventListener("click", function () {
          if (!state.editing) return;
          setMsg("attachMsg", T("attachUploading"));
          app.pickFromDrive().then(function (docs) {
            return app.attachDriveFiles(state.editing.id, docs);
          }).then(function (n) {
            setMsg("attachMsg", n ? T("attachDone") : "", n ? "success" : "");
            return loadAttachments();
          }).catch(function (err) {
            if (String(err && err.message) === "cancelled") { clearMsg("attachMsg"); return; }
            setMsg("attachMsg", T("attachFailed"), "error");
          });
        });

        var linkBtn = $("attachLinkBtn");
        if (linkBtn) linkBtn.addEventListener("click", function () {
          var url = String($("attachLink").value || "").trim();
          if (!url || !state.editing) return;
          setMsg("attachMsg", T("attachUploading"));
          app.addAttachmentLink(state.editing.id, url.split("/").pop() || url, url).then(function () {
            $("attachLink").value = "";
            setMsg("attachMsg", T("attachDone"), "success");
            return loadAttachments();
          }).catch(function () { setMsg("attachMsg", T("attachFailed"), "error"); });
        });

        var list = $("attachList");
        if (list) list.addEventListener("click", function (ev) {
          var openBtn = ev.target.closest("[data-attach-open]");
          var delBtn = ev.target.closest("[data-attach-del]");
          if (openBtn) {
            ev.preventDefault();
            var att = attachById(openBtn.dataset.attachOpen);
            if (!att) return;
            var w = window.open("about:blank", "_blank");
            app.attachmentUrl(att).then(function (url) {
              if (!url) { if (w) w.close(); return; }
              if (w) w.location = url; else window.location.assign(url);
            }).catch(function () { if (w) w.close(); setMsg("attachMsg", T("attachFailed"), "error"); });
          } else if (delBtn) {
            var target = attachById(delBtn.dataset.attachDel);
            if (!target) return;
            if (!window.confirm(T("attachDeleteConfirm"))) return;
            app.deleteAttachment(target).then(loadAttachments)
              .catch(function () { setMsg("attachMsg", T("attachFailed"), "error"); });
          }
        });
      }

      function closeEdit() {
        state.editing = null;
        hide("editPanel");
        clearMsg("editMsg");
      }

