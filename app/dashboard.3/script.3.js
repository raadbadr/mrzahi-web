      $("editCancelBtn").addEventListener("click", closeEdit);
      $("editForm").addEventListener("submit", function (ev) {
        ev.preventDefault();
        if (!state.editing) return;
        var title = $("editTitle").value.trim();
        if (!title) { setMsg("editMsg", T("titleRequired"), "error"); $("editTitle").focus(); return; }
        var trackerId = $("editTracker").value;
        if (!trackerId) { setMsg("editMsg", T("trackerRequired"), "error"); $("editTracker").focus(); return; }
        clearMsg("editMsg");
        var patch = {
          title: title,
          tracker_id: trackerId,
          due_at: fromLocalInput($("editDue").value),
          category: $("editCategory").value.trim() || null,
          assignee_id: $("editAssignee").value || null,
          amount: numOrNull($("editAmount").value),
          client_name: $("editClient").value.trim() || null,
          client_name_en: $("editClientEn").value.trim() || null,
          case_number: $("editCaseNumber").value.trim() || null,
          status: $("editStatus").value || "open",
          remind_before: $("editRemind").value || null
        };
        /* القائمة تعرض خمس مدد فقط. من ضبط تذكيره من البوت بمدة أخرى (يومين، ساعتين،
           شهرين) كانت قيمته تسقط إلى فارغ فيمحى تذكيره صامتا مع أي حفظ. */
        if (!patch.remind_before && state.editing.remind_before) delete patch.remind_before;
        /* data تستبدل كاملة عند الحفظ، فتدمج بيانات العقد فوق ما كان لا بدلا منه. */
        var cdata = contractRowData("edit");
        if (cdata) patch.data = Object.assign({}, state.editing.data || {}, cdata);
        var id = state.editing.id;
        guard(function () {
          $("editSaveBtn").disabled = true;
          return app.updateItem(id, patch).then(function () {
            toast("saved");
            closeEdit();
            return refresh();
          });
        }).then(function () { $("editSaveBtn").disabled = false; }, function (err) {
          $("editSaveBtn").disabled = false;
          fail(err, "editMsg");
        });
      });

      document.addEventListener("keydown", function (ev) {
        if (ev.key !== "Escape") return;
        if (!$("editPanel").hidden) closeEdit();
        else if (!$("addItemPanel").hidden) { hide("addItemPanel"); clearMsg("addMsg"); }
      });

      /* ---------- calendar ---------- */

      function startOfMonth(d) { return new Date(d.getFullYear(), d.getMonth(), 1); }

      function addDays(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n); }

      /* Grid always starts on Sunday; rows = as many full weeks as the month needs.
         الشهر هنا هو الشهر المعروض فعلا: ميلادي أو هجري بحسب الوضع. */
      function startOfDay(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()); }
      function calZoom() { return state.calZoom === "week" || state.calZoom === "day" ? state.calZoom : "month"; }

      function calRange() {
        var zoom = calZoom();
        if (zoom === "day") {
          var one = startOfDay(state.calDay || new Date());
          return { start: one, end: addDays(one, 1), cells: 1, first: one, days: 1, zoom: zoom };
        }
        if (zoom === "week") {
          var anchor = startOfDay(state.calDay || new Date());
          var wk = addDays(anchor, -anchor.getDay());
          return { start: wk, end: addDays(wk, 7), cells: 7, first: wk, days: 7, zoom: zoom };
        }
        var first = calendarIsHijri() ? startOfHijriMonth(state.month) : startOfMonth(state.month);
        var daysInMonth = calendarIsHijri()
          ? Math.round((shiftHijriMonth(first, 1) - first) / 86400000)
          : new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate();
        var rows = Math.ceil((first.getDay() + daysInMonth) / 7);
        var start = addDays(first, -first.getDay());
        var end = addDays(start, rows * 7);
        return { start: start, end: end, cells: rows * 7, first: first, days: daysInMonth, zoom: "month" };
      }

      function loadCalendar() {
        if (!state.calDay) state.calDay = new Date();
        var r = calRange();
        return app.listItems({ from: r.start.toISOString(), to: r.end.toISOString(), limit: 1000 }).then(function (items) {
          state.calAll = (items || []).filter(matchesView);
          state.calItems = applyCalFilter(state.calAll);
          renderCalendar();
        }).catch(function (err) {
          state.calItems = [];
          renderCalendar();
          fail(err);
        });
      }

      /* تقويم أم القرى عبر Intl: الشبكة نفسها تتبع الشهر الهجري في الوضع الهجري */
      /* اسم الشهر الهجري بلغة الواجهة نفسها (لا «ربيع» في الإنجليزية)، والأرقام غربية دائما */
      function hijriLocale() {
        var lo = app.lang();
        var base = lo === "ur" ? "ur-PK" : (lo === "ar" ? "ar-SA" : (lo === "fr" ? "fr-FR" : "en-US"));
        return base + "-u-ca-islamic-umalqura-nu-latn";
      }

      function hijriParts(date) {
        try {
          var parts = new Intl.DateTimeFormat("en-u-ca-islamic-umalqura", {
            day: "numeric", month: "numeric", year: "numeric"
          }).formatToParts(date);
          var out = {};
          parts.forEach(function (p) { if (p.type !== "literal") out[p.type] = parseInt(p.value, 10); });
          return out;
        } catch (e) { return null; }
      }

      function hijriTitle(date) {
        try {
          return new Intl.DateTimeFormat(hijriLocale(), { month: "long", year: "numeric" }).format(date);
        } catch (e) { return ""; }
      }

      function startOfHijriMonth(date) {
        var d = new Date(date.getFullYear(), date.getMonth(), date.getDate());
        var p = hijriParts(d);
        if (!p) return startOfMonth(date);
        var guard = 0;
        while (p && p.day > 1 && guard < 40) {
          d = new Date(d.getFullYear(), d.getMonth(), d.getDate() - (p.day - 1));
          p = hijriParts(d);
          guard++;
          if (p && p.day === 1) break;
        }
        return d;
      }

      function shiftHijriMonth(date, dir) {
        var start = startOfHijriMonth(date);
        var probe = new Date(start.getFullYear(), start.getMonth(), start.getDate() + (dir > 0 ? 31 : -2));
        return startOfHijriMonth(probe);
      }

      function calendarIsHijri() { return state.calMode === "hijri"; }

      /* فلاتر التقويم الماستر: تصنيف بلا إعادة جلب؛ الأوراق عناصر بنوع مستند، والمهام ما ليس قضية ولا مخالفة ولا ورقة */
      function calKind(it) {
        if (it && it.data && it.data.document_kind) return "documents";
        if (isCaseItem(it)) return "cases";
        if (isViolationItem(it)) return "violations";
        return "tasks";
      }
      function applyCalFilter(list) {
        var f = state.calFilter || "all";
        return f === "all" ? (list || []) : (list || []).filter(function (it) { return calKind(it) === f; });
      }
      function wireCalFilters() {
        var box = $("calFilters");
        if (!box) return;
        box.hidden = !!currentViewType();   /* الرئيسية وحدها: هي التقويم الماستر */
        box.addEventListener("click", function (ev) {
          var btn = ev.target.closest("[data-cal-filter]");
          if (!btn) return;
          state.calFilter = btn.getAttribute("data-cal-filter") || "all";
          box.querySelectorAll("[data-cal-filter]").forEach(function (b) {
            b.classList.toggle("is-active", b === btn);
            b.setAttribute("aria-pressed", b === btn ? "true" : "false");
          });
          state.calItems = applyCalFilter(state.calAll || state.calItems);
          renderCalendar();
        });
      }

      /* عنوان الشريط بحسب المدى المعروض: شهر، او نطاق الاسبوع، او اليوم كاملا */
      function calDayLabel(d, withWeekday) {
        if (calendarIsHijri()) {
          try {
            return new Intl.DateTimeFormat(hijriLocale(), withWeekday
              ? { weekday: "long", day: "numeric", month: "long", year: "numeric" }
              : { day: "numeric", month: "long", year: "numeric" }).format(d);
          } catch (e) { /* يسقط الى الميلادي */ }
        }
        var base = d.getDate() + " " + T("month" + (d.getMonth() + 1)) + " " + d.getFullYear();
        return withWeekday ? T(DAY_KEYS[d.getDay()]) + " " + base : base;
      }

      function calHeadTitle(r) {
        if (r.zoom === "day") return calDayLabel(r.start, true);
        if (r.zoom === "week") return calDayLabel(r.start) + " — " + calDayLabel(addDays(r.start, 6));
        return calendarIsHijri()
          ? hijriTitle(state.month)
          : T("month" + (state.month.getMonth() + 1)) + " " + state.month.getFullYear();
      }

      /* رقم اليوم في رأس العمود: هجري ومعه الميلادي في الوضع الهجري */
      function calDayNumber(d) {
        if (!calendarIsHijri()) return String(d.getDate());
        var hp = hijriParts(d);
        return hp ? hp.day + " · " + d.getDate() : String(d.getDate());
      }

      /* نصوص التنقل تتبع المدى، وزر المدى النشط يعلم */
      function syncCalNavLabels() {
        var z = calZoom();
        var pairs = [
          [$("calPrevBtn"), z === "week" ? "calPrevWeek" : z === "day" ? "calPrevDay" : "calPrev"],
          [$("calNextBtn"), z === "week" ? "calNextWeek" : z === "day" ? "calNextDay" : "calNext"]
        ];
        pairs.forEach(function (pair) {
          if (!pair[0]) return;
          pair[0].setAttribute("data-i18n", pair[1]);
          pair[0].textContent = T(pair[1]);
        });
        var box = $("calZoom");
        if (box) box.querySelectorAll("[data-cal-zoom]").forEach(function (b) {
          var on = b.getAttribute("data-cal-zoom") === z;
          b.classList.toggle("is-active", on);
          b.setAttribute("aria-pressed", on ? "true" : "false");
        });
      }

      function calChip(it) {
        var paper = paperKindOf(it);
        var chip = document.createElement("button");
        chip.type = "button";
        chip.className = "cal-chip " + (paper ? "is-paper" : "status-" + statusKeyOf(it));
        chip.textContent = paper ? paperEventLabel(it, paper) : (it.title || "");
        chip.title = chip.textContent;
        chip.dataset.id = it.id;
        /* الورقة الرسمية لا تسحب: تاريخها هو تاريخ انتهاء مستندها لا موعدا يزاح */
        if (paper) chip.dataset.paper = "1";
        else chip.dataset.drag = "1";
        return chip;
      }

      /* في الاسبوع واليوم يتسع المكان للوقت، فيسبق العنوان */
      function calChipTimed(it) {
        var chip = calChip(it);
        var when = it.due_at && app.fmtDate ? app.fmtDate(it.due_at, { timeOnly: true }) : "";
        if (when) {
          var span = document.createElement("span");
          span.className = "cal-chip-time";
          span.textContent = when;
          chip.insertBefore(span, chip.firstChild);
        }
        return chip;
      }

      function renderCalendar() {
        if (!state.month) return;
        var grid = $("calGrid");
        /* مصاريف التشغيل بلا تقويم (script.1.js يزيل calCard من الصفحة)، فعنصر
           التقويم غير موجود هنا؛ بلا هذا الحارس كانت الكتابة على null تسقط
           الوعد وتظهر «تعذر تحميل البيانات» في كل مرة. */
        if (!grid) return;
        var r = calRange();
        grid.innerHTML = "";
        grid.className = "cal-grid" + (r.zoom === "month" ? "" : " cal-grid--" + r.zoom);
        $("calTitle").textContent = calHeadTitle(r);
        syncCalNavLabels();

        var byDay = {};
        state.calItems.forEach(function (it) {
          if (!it.due_at) return;
          var d = new Date(it.due_at);
          if (isNaN(d.getTime())) return;
          var k = dateKey(d);
          (byDay[k] = byDay[k] || []).push(it);
        });
        /* داخل اليوم ترتب بالوقت: الاسبوع واليوم يعرضان الساعة، فالفوضى تظهر */
        Object.keys(byDay).forEach(function (k) {
          byDay[k].sort(function (a, b) { return new Date(a.due_at) - new Date(b.due_at); });
        });

        var todayKey = dateKey(new Date());

        if (r.zoom !== "month") {
          /* اسم اليوم داخل خليته لا في صف رؤوس منفصل: هكذا يصح العمود الواحد
             على الجوال كما تصح السبعة على الحاسب. واليوم يقوله العنوان فوق. */
          for (var j = 0; j < r.cells; j++) {
            var dd = addDays(r.start, j);
            var kk = dateKey(dd);
            var wcell = document.createElement("div");
            wcell.className = "cal-cell" + (kk === todayKey ? " is-today" : "");
            wcell.dataset.day = kk;
            if (r.zoom === "week") {
              var wday = document.createElement("div");
              wday.className = "cal-day";
              wday.textContent = T(DAY_KEYS[dd.getDay()]) + " " + calDayNumber(dd);
              wcell.appendChild(wday);
            }
            var rows = byDay[kk] || [];
            rows.forEach(function (it) { wcell.appendChild(calChipTimed(it)); });
            if (!rows.length && r.zoom === "day") {
              var empty = document.createElement("div");
              empty.className = "cal-empty";
              empty.textContent = T("calDayEmpty");
              wcell.appendChild(empty);
            }
            grid.appendChild(wcell);
          }
          return;
        }

        DAY_KEYS.forEach(function (k) {
          var h = document.createElement("div");
          h.className = "cal-dow";
          h.textContent = T(k);
          grid.appendChild(h);
        });

        var monthEnd = addDays(r.first, r.days);
        for (var i = 0; i < r.cells; i++) {
          var d = addDays(r.start, i);
          var key = dateKey(d);
          var outside = d < r.first || d >= monthEnd;
          var cell = document.createElement("div");
          cell.className = "cal-cell" +
            (outside ? " is-outside" : "") +
            (key === todayKey ? " is-today" : "");
          cell.dataset.day = key;
          var num = document.createElement("div");
          num.className = "cal-day";
          if (calendarIsHijri()) {
            var hp = hijriParts(d);
            num.textContent = hp ? String(hp.day) : String(d.getDate());
            var sub = document.createElement("span");
            sub.className = "cal-day-sub";
            sub.textContent = " · " + d.getDate();
            num.appendChild(sub);
          } else {
            num.textContent = String(d.getDate());
          }
          cell.appendChild(num);

          var list = byDay[key] || [];
          list.slice(0, MAX_CHIPS).forEach(function (it) { cell.appendChild(calChip(it)); });
          if (list.length > MAX_CHIPS) {
            var more = document.createElement("div");
            more.className = "cal-more";
            more.textContent = "+" + (list.length - MAX_CHIPS);
            more.title = fmt("moreItems", { n: list.length - MAX_CHIPS });
            cell.appendChild(more);
          }
          grid.appendChild(cell);
        }
      }

      /* الورقة الرسمية حدث بلونه: «انتهاء السجل التجاري»، والنقر يفتحها في المستندات */
      var PAPER_LABEL = {
        commercial_register: { ar: "السجل التجاري", en: "Commercial register", fr: "Registre de commerce", ur: "تجارتی رجسٹر" },
        vat_certificate: { ar: "الشهادة الضريبية", en: "VAT certificate", fr: "Certificat de TVA", ur: "ویٹ سرٹیفکیٹ" },
        gosi_certificate: { ar: "شهادة التأمينات", en: "GOSI certificate", fr: "Certificat GOSI", ur: "جی او ایس آئی سرٹیفکیٹ" },
        zakat_certificate: { ar: "شهادة الزكاة", en: "Zakat certificate", fr: "Certificat de zakat", ur: "زکوۃ سرٹیفکیٹ" },
        chamber_certificate: { ar: "شهادة الغرفة", en: "Chamber certificate", fr: "Certificat de chambre", ur: "چیمبر سرٹیفکیٹ" },
        saudization_certificate: { ar: "شهادة السعودة", en: "Saudization certificate", fr: "Certificat de saoudisation", ur: "سعودائزیشن سرٹیفکیٹ" },
        license: { ar: "الرخصة", en: "Licence", fr: "Licence", ur: "لائسنس" },
        lease_contract: { ar: "عقد الإيجار", en: "Lease contract", fr: "Bail", ur: "کرایہ نامہ" },
        insurance_policy: { ar: "وثيقة التأمين", en: "Insurance policy", fr: "Police d'assurance", ur: "انشورنس پالیسی" },
        id_document: { ar: "الهوية", en: "ID", fr: "Pièce d'identité", ur: "شناخت" },
        passport: { ar: "الجواز", en: "Passport", fr: "Passeport", ur: "پاسپورٹ" },
        driving_license: { ar: "رخصة القيادة", en: "Driving licence", fr: "Permis de conduire", ur: "ڈرائیونگ لائسنس" },
        vehicle_registration: { ar: "الاستمارة", en: "Vehicle registration", fr: "Carte grise", ur: "گاڑی رجسٹریشن" },
        power_of_attorney: { ar: "الوكالة", en: "Power of attorney", fr: "Procuration", ur: "وکالت نامہ" },
        employment_contract: { ar: "عقد العمل", en: "Employment contract", fr: "Contrat de travail", ur: "ملازمت کا معاہدہ" },
        articles_of_association: { ar: "عقد التأسيس", en: "Articles of association", fr: "Statuts", ur: "بانی معاہدہ" },
        bylaws: { ar: "النظام الأساسي", en: "Bylaws", fr: "Statuts", ur: "بنیادی قواعد" }
      };
      var EXPIRY_WORD = { ar: "انتهاء", en: "Expires", fr: "Expiration", ur: "اختتام" };

      function paperKindOf(item) {
        var kind = ((item && item.data) || {}).document_kind;
        return kind && PAPER_LABEL[kind] ? kind : "";
      }

      function paperEventLabel(item, kind) {
        var l = (app && app.lang && app.lang()) || document.documentElement.lang || "ar";
        var name = PAPER_LABEL[kind][l] || PAPER_LABEL[kind].ar;
        return (EXPIRY_WORD[l] || EXPIRY_WORD.ar) + " " + name;
      }

      $("calGrid").addEventListener("click", function (ev) {
        if (suppressCalClick) return;   /* هذه نهاية سحب لا نقرة */
        var c = ev.target.closest(".cal-chip");
        if (!c) return;
        if (c.dataset.paper) { window.location.href = "/app/documents.html#" + encodeURIComponent(c.dataset.id); return; }
        var it = findItem(c.dataset.id);
        if (it) openEdit(it);
      });

      /* ---------- سحب الموعد الى يوم اخر، كما في تقويم جوجل ----------
         بالفارة يبدا السحب بعد 6 بكسل، وباللمس بعد ضغطة مطولة، فلا يختطف
         تمرير الصفحة. الوقت يبقى كما هو ويتغير التاريخ وحده. */
      var calDrag = null, suppressCalClick = false;

      function calCellAt(x, y) {
        var el = document.elementFromPoint(x, y);
        return el ? el.closest(".cal-cell[data-day]") : null;
      }

      function clearDropMark() {
        var grid = $("calGrid");
        if (!grid) return;
        grid.querySelectorAll(".cal-cell.is-drop").forEach(function (c) { c.classList.remove("is-drop"); });
      }

      function beginCalDrag() {
        if (!calDrag || calDrag.active) return;
        calDrag.active = true;
        document.body.classList.add("cal-dragging");
        calDrag.chip.classList.add("is-dragging");
        var ghost = calDrag.chip.cloneNode(true);
        ghost.classList.remove("is-dragging");
        ghost.classList.add("cal-ghost");
        ghost.style.width = calDrag.chip.getBoundingClientRect().width + "px";
        document.body.appendChild(ghost);
        calDrag.ghost = ghost;
        try { calDrag.chip.setPointerCapture(calDrag.pointerId); } catch (e) { /* غير مدعوم */ }
      }

      function endCalDrag(commit, x, y) {
        if (!calDrag) return;
        var d = calDrag;
        calDrag = null;
        if (d.timer) clearTimeout(d.timer);
        if (d.ghost && d.ghost.parentNode) d.ghost.parentNode.removeChild(d.ghost);
        if (d.chip) d.chip.classList.remove("is-dragging");
        document.body.classList.remove("cal-dragging");
        clearDropMark();
        if (!d.active) return;
        /* النقرة التالية مباشرة هي اثر السحب لا رغبة في الفتح */
        suppressCalClick = true;
        setTimeout(function () { suppressCalClick = false; }, 0);
        if (!commit) return;
        var cell = calCellAt(x, y);
        var to = cell && cell.dataset.day;
        if (!to || to === d.fromDay) return;
        moveItemToDay(d.id, to);
      }

      function moveItemToDay(id, dayKey) {
        var it = findItem(id);
        if (!it || !it.due_at) return;
        var old = new Date(it.due_at);
        if (isNaN(old.getTime())) return;
        var p = String(dayKey).split("-");
        var next = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]), old.getHours(), old.getMinutes(), 0, 0);
        guard(function () {
          return app.updateItem(id, { due_at: next.toISOString() }).then(function () {
            toast("calMoved");
            return refresh();
          });
        }).catch(function (err) { fail(err); loadCalendar(); });
      }

      $("calGrid").addEventListener("pointerdown", function (ev) {
        if (ev.button != null && ev.button !== 0) return;
        var chip = ev.target.closest(".cal-chip[data-drag]");
        if (!chip) return;
        var cell = chip.closest(".cal-cell[data-day]");
        if (!cell) return;
        calDrag = { id: chip.dataset.id, chip: chip, fromDay: cell.dataset.day,
                    x0: ev.clientX, y0: ev.clientY, pointerId: ev.pointerId,
                    touch: ev.pointerType === "touch", active: false, ghost: null, timer: null };
        if (calDrag.touch) calDrag.timer = setTimeout(beginCalDrag, 350);
      });

      document.addEventListener("pointermove", function (ev) {
        if (!calDrag) return;
        var far = Math.abs(ev.clientX - calDrag.x0) + Math.abs(ev.clientY - calDrag.y0);
        if (!calDrag.active) {
          /* اصبع يتحرك قبل ان تكتمل الضغطة المطولة: هذا تمرير للصفحة لا سحب */
          if (calDrag.touch) { if (far > 10) endCalDrag(false); return; }
          if (far < 6) return;
          beginCalDrag();
        }
        ev.preventDefault();
        calDrag.ghost.style.left = ev.clientX + "px";
        calDrag.ghost.style.top = ev.clientY + "px";
        clearDropMark();
        var over = calCellAt(ev.clientX, ev.clientY);
        if (over && over.dataset.day !== calDrag.fromDay) over.classList.add("is-drop");
      }, { passive: false });

      document.addEventListener("pointerup", function (ev) { endCalDrag(true, ev.clientX, ev.clientY); });
      document.addEventListener("pointercancel", function () { endCalDrag(false); });
      function setAnchorFromMonth() {
        state.calAnchor = new Date(state.month.getFullYear(), state.month.getMonth(), state.month.getDate() + 15);
      }

      /* خطوة التنقل بحجم المدى المعروض: شهر او اسبوع او يوم */
      function calStep(dir) {
        var z = calZoom();
        if (z === "day" || z === "week") {
          state.calDay = addDays(state.calDay || new Date(), dir * (z === "day" ? 1 : 7));
          state.month = calendarIsHijri() ? startOfHijriMonth(state.calDay) : startOfMonth(state.calDay);
          state.calAnchor = new Date(state.calDay.getTime());
          loadCalendar();
          return;
        }
        state.month = calendarIsHijri()
          ? shiftHijriMonth(state.month, dir)
          : new Date(state.month.getFullYear(), state.month.getMonth() + dir, 1);
        setAnchorFromMonth();
        state.calDay = new Date(state.month.getTime());
        loadCalendar();
      }
      $("calPrevBtn").addEventListener("click", function () { calStep(-1); });
      $("calNextBtn").addEventListener("click", function () { calStep(1); });

      /* تبديل المدى: اليوم المرساة هو اليوم ان كان داخل الشهر المعروض، والا اوله */
      $("calZoom").addEventListener("click", function (ev) {
        var btn = ev.target.closest("[data-cal-zoom]");
        if (!btn) return;
        var want = btn.getAttribute("data-cal-zoom");
        if (want !== "week" && want !== "day") want = "month";
        if (want === calZoom()) return;
        state.calZoom = want;
        try { localStorage.setItem("tracker_cal_zoom", want); } catch (e) { /* تخزين محجوب */ }
        if (want !== "month") {
          var now = new Date();
          var monthStart = calendarIsHijri() ? startOfHijriMonth(state.month) : startOfMonth(state.month);
          var monthEnd = calendarIsHijri() ? shiftHijriMonth(monthStart, 1) : new Date(monthStart.getFullYear(), monthStart.getMonth() + 1, 1);
          state.calDay = (now >= monthStart && now < monthEnd) ? now : monthStart;
        }
        loadCalendar();
      });

      document.addEventListener("click", function (ev) {
        var btn = ev.target.closest("[data-cal-mode]");
        if (!btn) return;
        state.calMode = btn.dataset.calMode === "hijri" ? "hijri" : "greg";
        try { localStorage.setItem("tracker_cal_mode", state.calMode); } catch (e) { /* ignore */ }
        var g = $("calGregBtn"), h = $("calHijriBtn");
        if (g) g.classList.toggle("is-active", state.calMode === "greg");
        if (h) h.classList.toggle("is-active", state.calMode === "hijri");
        var anchor = state.calAnchor || new Date();
        state.month = calendarIsHijri() ? startOfHijriMonth(anchor) : startOfMonth(anchor);
        loadCalendar();
        /* المدى لا يتغير بتغير التقويم: الاسبوع يبقى اسبوعا واليوم يوما */
      });
      wireCalFilters();
      $("calTodayBtn").addEventListener("click", function () {
        var now = new Date();
        state.month = calendarIsHijri() ? startOfHijriMonth(now) : startOfMonth(now);
        state.calDay = now;
        state.calAnchor = new Date(now.getTime());
        loadCalendar();
      });

      /* ---------- language change hook (called from setLang) ---------- */

      window.__dashboardRerender = function () {
        if (!app || !state.org) return;
        renderTopBar();
        renderSelects();
        renderList();
        renderCalendar();
        renderTimeline(tlState.rows, tlState.stats);   /* الخط الزمني بلغة الواجهة الجديدة، بلا تحميل */
        paintTiles();                                  /* أسماء المربعات بلغة الواجهة الجديدة من أرقامها المحفوظة */
      };

      /* Deferred scripts (supabase-js, app.js, common.js) run before DOMContentLoaded. */
      if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
      else boot();
    })();
  