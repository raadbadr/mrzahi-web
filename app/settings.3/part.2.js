      function fillOrgProfile() {
        return app.orgProfile().then(function (p) {
          state.orgProfile = p || null;
          var addr = (p && p.national_address) || {};
          if (el("opEntityType")) el("opEntityType").value = (p && p.entity_type) || "company";
          applyEntityType();
          Object.keys(OP_FIELDS).forEach(function (id) {
            var node = el(id); if (node) node.value = (p && p[OP_FIELDS[id]]) || "";
          });
          if (el("opShortAddress")) el("opShortAddress").value = addr.short || "";
          var canEdit = ["owner", "admin"].indexOf(app.role ? app.role() : "") !== -1;
          fillPacks(p);
          el("orgProfileForm").querySelectorAll("input,select,button").forEach(function (n) { n.disabled = !canEdit; });
          if (!canEdit) setMsg("opMsg", t("opAdminOnly"), "");
        }).catch(function () { /* بطاقة اختيارية: لا تعطل بقية الإعدادات */ });
      }

      /* واجهة الحساب: تظهر القائمة فقط حين تكون هناك أكثر من واجهة متاحة */
      var packsLoaded = null;
      function fillPacks(profile) {
        var sel = el("opPack"), field = el("opPackField");
        if (!sel || !field || !app.listPacks) return;
        (packsLoaded ? Promise.resolve(packsLoaded) : app.listPacks()).then(function (rows) {
          packsLoaded = rows || [];
          if (packsLoaded.length < 2) { field.hidden = true; return; }
          var cur = (profile && profile.ui_pack) || (app.pack && app.pack.pack) || "";
          var html = packsLoaded.map(function (pk) {
            var name = (pk.names && (pk.names[app.lang()] || pk.names.ar)) || pk.key;
            return '<option value="' + esc(pk.key) + '"' + (pk.key === cur ? " selected" : "") + ">" + esc(name) + "</option>";
          }).join("");
          if (sel.innerHTML !== html) sel.innerHTML = html;
          sel.value = cur || sel.value;
          field.hidden = false;
        }).catch(function () { field.hidden = true; });
      }

      /* الحساب الفردي: شخص يرتب أوراقه، فلا تعرض عليه حقول المنشآت التجارية. */
      var COMMERCIAL_ONLY = ["opCr", "opVat", "opUnified", "opLicense"];
      function applyEntityType() {
        var sel = el("opEntityType");
        if (!sel) return;
        var person = app.isPersonType ? app.isPersonType(sel.value) : sel.value === "individual";
        COMMERCIAL_ONLY.forEach(function (id) {
          var node = el(id), box = node && node.closest(".settings-field");
          if (box) box.hidden = person;
        });
        var label = document.querySelector('label[for="opLegalName"]');
        if (label) {
          label.dataset.i18n = person ? "opFullName" : "opLegalName";
          label.textContent = t(person ? "opFullName" : "opLegalName");
        }
      }

      function saveOrgProfile(ev) {
        if (ev) ev.preventDefault();
        var iban = String(el("opIban").value || "").replace(/\s+/g, "").toUpperCase();
        if (iban && !/^SA\d{22}$/.test(iban)) { setMsg("opMsg", t("opBadIban"), "error"); return; }
        var vat = String(el("opVat").value || "").replace(/\s+/g, "");
        if (vat && !/^3\d{13}3$/.test(vat)) { setMsg("opMsg", t("opBadVat"), "error"); return; }
        var shortAddr = String(el("opShortAddress").value || "").replace(/\s+/g, "").toUpperCase();
        if (shortAddr && !/^[A-Z]{4}\d{4}$/.test(shortAddr)) { setMsg("opMsg", t("opBadShortAddress"), "error"); return; }
        var row = { entity_type: el("opEntityType").value, national_address: shortAddr ? { short: shortAddr } : {} };
        Object.keys(OP_FIELDS).forEach(function (id) { row[OP_FIELDS[id]] = String(el(id).value || "").trim(); });
        if (app.isPersonType && app.isPersonType(row.entity_type)) {
          COMMERCIAL_ONLY.forEach(function (id) { row[OP_FIELDS[id]] = ""; });
        }
        row.iban = iban; row.vat_number = vat;
        var packSel = el("opPack");
        var packWanted = packSel && !el("opPackField").hidden ? packSel.value : null;
        var packChanged = !!packWanted && packWanted !== ((app.pack && app.pack.pack) || "");
        el("opSaveBtn").disabled = true;
        app.saveOrgProfile(row).then(function (saved) {
          state.orgProfile = saved;
          if (!packChanged) return null;
          /* الواجهة تتبدل كاملة، فتعاد الصفحة مرة واحدة بدل إعادة رسم كل شيء أمام المستخدم */
          return app.setOrgPack(packWanted).then(function () { window.location.reload(); });
        }).then(function () {
          setMsg("opMsg", t("opSaved"), "success");
        }).catch(function () {
          setMsg("opMsg", t("genericError"), "error");
        }).finally(function () { el("opSaveBtn").disabled = false; });
      }

      function boot() {
        app = window.trackerApp;
        if (!app || !app.ready) { showUnavailable(); return; }
        app.ready.then(function (st) {
          if (!st || st.unavailable || app.unavailable) { showUnavailable(); return; }
          show("loadingCard", false);
          show("settingsMain", true);
          state.loaded = true;
          fillProfile();
          fillOrgProfile();

          el("profileForm").addEventListener("submit", saveProfile);
          el("orgProfileForm").addEventListener("submit", saveOrgProfile);
          el("opEntityType").addEventListener("change", applyEntityType);
          el("channelsGrid").addEventListener("click", onChannelAction);
          el("channelsGrid").addEventListener("click", onChannelToggle);
          el("channelsGrid").addEventListener("submit", onSmsSubmit);
          el("rulesWrap").addEventListener("click", onRuleAction);
          el("copyUrlBtn").addEventListener("click", copyCalendarUrl);
          if (el("copyDeviceBtn")) el("copyDeviceBtn").addEventListener("click", copyDeviceUrl);
          if (el("profileTimeFormat")) el("profileTimeFormat").addEventListener("click", function (ev) {
            var b = ev.target.closest(".cal-mode");
            if (b) setTimeFormat(b.getAttribute("data-time-format"));
          });
          el("upgradeBtn").addEventListener("click", submitUpgrade);
          /* العودة من بوابة الدفع: تقال النتيجة وينظف العنوان. */
          try {
            var payFlag = new URLSearchParams(window.location.search).get("pay");
            if (payFlag) {
              setMsg("upgradeMsg", t(payFlag === "done" ? "payDone" : payFlag === "failed" ? "payFailed" : "payCancelled"),
                     payFlag === "done" ? "success" : "error");
              window.history.replaceState(null, "", window.location.pathname + window.location.hash);
            }
          } catch (e) { /* تجاهل */ }
          /* تغيير الباقة يعيد بناء المدد اولا: بعض الباقات سنوية فقط */
          el("upgradePlan").addEventListener("change", function () { fillUpgradePeriod(); renderUpgradePrice(); });
          el("upgradePeriod").addEventListener("change", renderUpgradePrice);
          el("storageDriveToggle").addEventListener("change", onDriveToggle);
          document.addEventListener("tracker:drive", renderDriveSwitch);

          if (app.org && el("orgNameInput")) el("orgNameInput").value = app.org.name || "";
          el("orgSaveBtn").addEventListener("click", function () {
            var name = String(el("orgNameInput").value || "").trim();
            if (!name) return;
            el("orgSaveBtn").disabled = true;
            app.renameOrg(name).then(function () {
              setMsg("orgMsg", t("orgSaved"), "success");
            }).catch(function () {
              setMsg("orgMsg", t("genericError"), "error");
            }).finally(function () { el("orgSaveBtn").disabled = false; });
          });
          el("orgDeleteBtn").addEventListener("click", function () {
            if (!app.org) return;
            if (!window.confirm(t("deleteOrgConfirm").split("{name}").join(app.org.name || ""))) return;
            app.deleteOrg().then(function () { window.location.href = "/app/dashboard.html"; })
              .catch(function () { setMsg("orgMsg", t("genericError"), "error"); });
          });
          var adBtn = el("accountDeleteBtn");
          if (adBtn) adBtn.addEventListener("click", function () {
            if (!window.confirm(t("deleteAccountConfirm"))) return;
            adBtn.disabled = true;
            app.requestAccountDeletion().then(function () {
              setMsg("accountDeleteMsg", t("deleteAccountScheduled"), "success");
              setTimeout(function () {
                try { localStorage.removeItem("tracker_org"); } catch (e) { /* ignore */ }
                var go = function () { window.location.href = "/login.html"; };
                window.trackerAuth.signOut().then(go).catch(go);
              }, 1500);
            }).catch(function (err) {
              adBtn.disabled = false;
              if (err && err.code === "OWNER_HAS_TEAM") {
                var names = (err.blockingOrgs || []).join("، ");
                setMsg("accountDeleteMsg", t("deleteAccountBlocked").split("{orgs}").join(names), "error");
              } else {
                setMsg("accountDeleteMsg", t("genericError"), "error");
              }
            });
          });
          try { wireApi(); } catch (e) { if (window.console) console.warn("api card:", e); }
          el("regenerateBtn").addEventListener("click", regenerateCalendar);
          var soBtn = el("signOutBtn");
          if (soBtn) soBtn.addEventListener("click", signOut);

          /* Plan limits first: they decide which channels the rules and cards may offer. */
          return loadSubscription().then(function () {
            renderStorage();
            return Promise.all([
              loadConfig().then(function () { return reloadLinks(); }).then(linkFromBotToken).then(finishDriveConnect),
              loadRules(),
              loadCalendar()
            ]);
          });
        }).catch(function (err) {
          if (window.console) console.error("settings:", err);
          toast(errorMessage(err), "error");
        });
      }

      if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
      else boot();
    })();
  