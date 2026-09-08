        /* Google Drive: الملف يبقى في درايف المستخدم، ننزله ليقرأه المحلل ونربط رابطه بالعنصر. */
        function syncDriveBtn() {
          var b = $("docDriveBtn");
          if (b) b.hidden = !(app && app.driveAvailable && app.driveAvailable());
        }
        document.addEventListener("tracker:drive", syncDriveBtn);
        syncDriveBtn();
        $("docDriveBtn").addEventListener("click", function () {
          var btn = this; btn.disabled = true;
          setStatus(t("docReading"));
          app.pickFromDrive({ multi: false }).then(function (docs) {
            var picked = docs && docs[0];
            if (!picked) throw new Error("cancelled");
            return app.driveDownload(picked).then(function (file) {
              state.driveDoc = picked;
              handleFile(file);
            });
          }).catch(function (err) {
            state.driveDoc = null;
            setStatus(String((err && err.message) || "") === "cancelled" ? "" : t("docDriveFailed"),
                      String((err && err.message) || "") === "cancelled" ? "" : "error");
          }).finally(function () { btn.disabled = false; });
        });
        $("docFile").addEventListener("change", function () { state.driveDoc = null; handleFile(this.files && this.files[0]); });
        var dz = $("docDrop");
        dz.addEventListener("dragover", function (e) { e.preventDefault(); dz.classList.add("is-over"); });
        dz.addEventListener("dragleave", function () { dz.classList.remove("is-over"); });
        dz.addEventListener("drop", function (e) { e.preventDefault(); dz.classList.remove("is-over"); handleFile(e.dataTransfer.files && e.dataTransfer.files[0]); });
        $("docForm").addEventListener("submit", save);
        $("docProfileApply").addEventListener("click", applyProfilePatch);
        $("docProfileSkip").addEventListener("click", function () { state.profilePatch = null; show("docProfileAsk", false); });
        $("docCancelBtn").addEventListener("click", function () {
          show("docForm", false); show("docDetails", false); show("docProfileAsk", false);
          state.file = null; state.driveDoc = null; state.details = null; state.detailLabels = null; state.profilePatch = null;
          $("docFile").value = ""; setStatus("");
        });
        $("docsBody").addEventListener("click", function (e) {
          var btn = e.target.closest("[data-details]");
          if (!btn) return;
          e.preventDefault();
          var row = $("docsBody").querySelector('[data-details-for="' + btn.getAttribute("data-details") + '"]');
          if (!row) return;
          row.hidden = !row.hidden;
          btn.setAttribute("aria-expanded", row.hidden ? "false" : "true");
        });
        $("filterKind").addEventListener("change", function () { state.kind = this.value; render(); });
        /* تعديل اي رقم قرأه المحلل: يكتب في الورقة كما يكتبه صاحبها */
        $("docDetailRows").addEventListener("input", function (ev) {
          var el = ev.target.closest ? ev.target.closest("[data-detail-key]") : null;
          if (!el) return;
          var key = el.getAttribute("data-detail-key");
          if (!state.details) state.details = {};
          state.details[key] = String(el.value || "").trim();
        });
        $("filterSearch").addEventListener("input", function () { state.search = this.value.trim(); render(); });
        $("papersBody").addEventListener("click", function (e) {
          var btn = e.target.closest("[data-paper-details]");
          if (!btn) return;
          e.preventDefault();
          var line = $("papersBody").querySelector('[data-paper-details-for="' + btn.getAttribute("data-paper-details") + '"]');
          if (!line) return;
          line.hidden = !line.hidden;
          btn.setAttribute("aria-expanded", line.hidden ? "false" : "true");
        });
        $("papersStats").addEventListener("click", function (e) {
          var tile = e.target.closest("[data-paper-state]");
          if (!tile) return;
          e.preventDefault();
          var pick = tile.getAttribute("data-paper-state");
          state.paperState = state.paperState === pick ? "" : pick;
          renderPapers();
          render();
        });
        $("papersBody").addEventListener("click", function (e) {
          var btn = e.target.closest("[data-paper-add]");
          if (!btn) return;
          e.preventDefault();
          state.pendingKind = btn.getAttribute("data-paper-add");
          $("docFile").click();
        });
        $("papersBody").addEventListener("click", function (e) {
          var pat = e.target.closest("[data-paper-attach]");
          if (pat) {
            e.preventDefault();
            var picker = $("docAttachInput");
            picker.dataset.item = pat.dataset.paperAttach;
            picker.click();
            return;
          }
          var open = e.target.closest("[data-paper-open]"), get = e.target.closest("[data-paper-get]");
          if (!open && !get) return;
          e.preventDefault();
          var att = attachmentById((open || get).getAttribute(open ? "data-paper-open" : "data-paper-get"));
          if (!att) return;
          /* النافذة تفتح مع النقرة لا بعد الوعد: سفاري يحجب ما يفتح لاحقا */
          var win = open ? window.open("about:blank", "_blank") : null;
          app.attachmentUrl(att, open ? undefined : { download: att.name || true }).then(function (u) {
            if (!u) { if (win) win.close(); return; }
            if (open) { if (win) win.location = u; else window.location.assign(u); return; }
            var a = document.createElement("a");
            a.href = u; a.download = att.name || "document"; a.rel = "noopener";
            document.body.appendChild(a); a.click(); a.remove();
          }).catch(function () { if (win) win.close(); setStatus(t("docFailed"), "error"); });
        });
        $("docAttachInput").addEventListener("change", function () {
          var file = this.files && this.files[0];
          var itemId = this.dataset.item;
          this.value = "";
          if (!file || !itemId) return;
          setStatus(t("docSaving"));
          app.uploadAttachment(itemId, file).then(function () {
            setStatus(t("docFileAdded"), "success");
            return loadAll();
          }).catch(function (err) {
            var code = String((err && (err.message || err.code)) || "");
            setStatus(code.indexOf("PLAN_LIMIT_STORAGE") !== -1 ? t("docStorageLimit") : t("docFileFailed"), "error");
          });
        });
        $("docsBody").addEventListener("click", function (e) {
          var at = e.target.closest("[data-attach]");
          if (at) {
            e.preventDefault();
            var picker = $("docAttachInput");
            picker.dataset.item = at.dataset.attach;
            picker.click();
            return;
          }
          var g = e.target.closest("[data-get]");
          if (g) {
            e.preventDefault();
            var gatt = attachmentById(g.dataset.get);
            if (!gatt) return;
            app.attachmentUrl(gatt, { download: gatt.name || true }).then(function (u) {
              if (!u) return;
              var link = document.createElement("a");
              link.href = u; link.download = gatt.name || "document"; link.rel = "noopener";
              document.body.appendChild(link); link.click(); link.remove();
            }).catch(function () { setStatus(t("docFailed"), "error"); });
            return;
          }
          var o = e.target.closest("[data-open]"), d = e.target.closest("[data-del]");
          if (o) {
            e.preventDefault();
            var att = null; Object.keys(state.attachments).forEach(function (k) { state.attachments[k].forEach(function (a) { if (a.id === o.dataset.open) att = a; }); });
            if (att) {
              var w = window.open("about:blank", "_blank");
              app.attachmentUrl(att).then(function (u) {
                if (!u) { if (w) w.close(); return; }
                if (w) w.location = u; else window.location.assign(u);
              }).catch(function () { if (w) w.close(); });
            }
          } else if (d) {
            if (!window.confirm(t("docDeleteConfirm"))) return;
            app.deleteItem(d.dataset.del).then(loadDocs).catch(function () { setStatus(t("docFailed"), "error"); });
          }
        });
      }

      window.__docsRefresh = function () { renderKindSelects(); render(); renderPapers(); };

      function boot() {
        app = window.trackerApp;
        if (!app || !app.ready) { show("loadingCard", false); show("unavailableCard", true); return; }
        app.ready.then(function (res) {
          show("loadingCard", false);
          if (!res || res.unavailable || app.unavailable) { show("unavailableCard", true); return; }
          if (!app.org) { show("noOrgCard", true); return; }
          renderKindSelects(); wire();
          show("docsView", true);
          return loadAll();
        }).catch(function () { show("loadingCard", false); show("unavailableCard", true); });
      }
      if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot); else boot();
    })();
  