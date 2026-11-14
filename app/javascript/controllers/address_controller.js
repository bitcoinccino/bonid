// app/javascript/controllers/address_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "department", "arrondissement", "commune", "section", "postalCode",
    "spinner", "error"
  ];

  // Optional: text shown inside a dropdown while its options load
  // (data-address-loading-value). Falls back to "…".
  static values = { loading: String };

  initialize() {
    // One counter per level: a slow response for an older choice must never
    // overwrite the options for the newer one (fast changes on mobile).
    this._seq = { arr: 0, com: 0, sec: 0, postal: 0 };
  }

  async connect() {
    console.log("📍 AddressController connected");

    // Early exit if no department target - nothing to cascade from
    if (!this.hasDepartmentTarget) {
      console.log("ℹ️ No department target found - address controller inactive");
      return;
    }

    try {
      this._hideError();

      // Check if we're in 3-level mode (no arrondissement) or 4-level mode
      const is3LevelCascade = !this.hasArrondissementTarget;

      if (is3LevelCascade) {
        // 3-level cascade: Department → Commune → Section
        console.log("📍 Using 3-level cascade (Department → Commune → Section)");
        await this._init3LevelCascade();
      } else {
        // 4-level cascade: Department → Arrondissement → Commune → Section
        console.log("📍 Using 4-level cascade (Department → Arrondissement → Commune → Section)");
        await this._init4LevelCascade();
      }
    } catch (error) {
      console.error("Initialization failed:", error);
      this._showError();
    }
  }

  // 3-level cascade initialization (Department → Commune → Section)
  async _init3LevelCascade() {
    // Department is always enabled
    if (this.hasDepartmentTarget) {
      this.departmentTarget.disabled = false;

      const deptSelected = this.departmentTarget.dataset?.selected;

      if (deptSelected) {
        console.log("🔄 3-level: Prefilling from department:", deptSelected);

        // Load communes for the selected department
        await this.loadCommunesFromDepartment(
          { target: { value: deptSelected } },
          true
        );

        const comSelected = this.hasCommuneTarget ? this.communeTarget.dataset?.selected : null;
        if (comSelected) {
          // Load sections for the selected commune
          await this.loadCommunalSections(
            { target: { value: comSelected } },
            true
          );

          // Load postal code if section is pre-selected
          const secSelected = this.hasSectionTarget ? this.sectionTarget.dataset?.selected : null;
          if (secSelected && this.hasPostalCodeTarget) {
            await this.loadPostalCode(
              { target: { value: secSelected } },
              true
            );
          }
        }
      } else {
        console.log("ℹ️ No dept selected—manual entry enabled");
      }
    } else {
      // No department target - this address controller instance doesn't have the required elements
      console.log("ℹ️ No department target found - skipping cascade initialization");
    }
  }

  // 4-level cascade initialization (Department → Arrondissement → Commune → Section)
  async _init4LevelCascade() {
    this._disableAllExcept(this.departmentTarget);

    const deptSelected = this.departmentTarget?.dataset?.selected;
    if (deptSelected && this.hasDepartmentTarget) {
      console.log("🔄 4-level: Starting silent chain for dept:", deptSelected);

      await this.loadArrondissements(
        { target: { value: deptSelected, dataset: { slugMapValue: this.departmentTarget.dataset.slugMapValue } } },
        true
      );

      const arrSelected = this.arrondissementTarget?.dataset?.selected;
      if (arrSelected && this.hasArrondissementTarget) {
        await this.loadCommunes(
          { target: { value: arrSelected } },
          true
        );

        const comSelected = this.communeTarget?.dataset?.selected;
        if (comSelected && this.hasCommuneTarget) {
          await this.loadCommunalSections(
            { target: { value: comSelected } },
            true
          );

          const secSelected = this.sectionTarget?.dataset?.selected;
          if (secSelected && this.hasSectionTarget) {
            await this.loadPostalCode(
              { target: { value: secSelected } },
              true
            );
          }
        }
      }
    } else {
      console.log("ℹ️ No dept selected—manual entry enabled");
      this.departmentTarget.disabled = false;
    }
  }

  // Add silent param to loaders (skips loading UI)
  async loadArrondissements(event, silent = false) {
    const departmentId = event.target.value;
    const slugMap = JSON.parse(event.target.dataset.slugMapValue || "{}");
    const slug = slugMap[departmentId];

    // A real choice by the citizen: forget the saved downstream picks so the
    // old arrondissement/commune/section can't snap back into place.
    if (!silent) this._forgetSaved(this.arrondissementTarget, this.communeTarget, this.sectionTarget);

    this._clear(this.arrondissementTarget);
    this._clear(this.communeTarget);
    this._clear(this.sectionTarget);
    this._clearPostal();
    this._disableAllExcept();

    if (!slug) {
      if (departmentId) console.warn("No slug for department:", departmentId);
      return;
    }

    await this._fetchInto("arr", this.arrondissementTarget,
      `/departments/${slug}/arrondissements`, silent);
  }

  // Load communes from arrondissement (4-level cascade)
  async loadCommunes(event, silent = false) {
    const id = event.target.value;

    if (!silent) this._forgetSaved(this.communeTarget, this.sectionTarget);
    this._clear(this.communeTarget);
    this._clear(this.sectionTarget);
    this._clearPostal();

    if (!id) return;

    await this._fetchInto("com", this.communeTarget, `/arrondissements/${id}/communes`, silent);
  }

  // Load communes directly from department (3-level cascade, skips arrondissement)
  async loadCommunesFromDepartment(event, silent = false) {
    const departmentId = event.target.value;

    if (!silent && this.hasCommuneTarget) this._forgetSaved(this.communeTarget, this.hasSectionTarget ? this.sectionTarget : null);
    if (this.hasCommuneTarget) this._clear(this.communeTarget);
    if (this.hasSectionTarget) this._clear(this.sectionTarget);
    this._clearPostal();

    if (!departmentId || !this.hasCommuneTarget) return;

    await this._fetchInto("com", this.communeTarget, `/departments/${departmentId}/communes`, silent);
  }

  // Load sections from commune (alias for loadCommunalSections for consistency)
  async loadSections(event, silent = false) {
    return this.loadCommunalSections(event, silent);
  }

  async loadCommunalSections(event, silent = false) {
    const id = event.target.value;

    if (!silent && this.hasSectionTarget) this._forgetSaved(this.sectionTarget);
    if (this.hasSectionTarget) this._clear(this.sectionTarget);
    this._clearPostal();

    if (!id || !this.hasSectionTarget) return;

    await this._fetchInto("sec", this.sectionTarget, `/communes/${id}/communal_sections`, silent);
  }

  async loadPostalCode(event, silent = false) {
    if (!this.hasPostalCodeTarget) return;

    const id = event.target.value;
    const seq = ++this._seq.postal;
    this._clearPostal();
    if (!id) return;

    if (!silent) this._startLoading();
    try {
      const response = await fetch(`/communal_sections/${id}/postal_code`);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      if (seq !== this._seq.postal) return; // a newer section was picked
      // Leave it empty rather than inventing a code when none is on file.
      this.postalCodeTarget.value = data.postal_code || "";
    } catch (error) {
      console.error("Failed to load postal code:", error);
      if (!silent) this._showError();
    } finally {
      if (!silent) this._endLoading();
    }
  }

  retry() {
    this._hideError();
    this.connect(); // re-run the full logic
  }

  // === Helpers ===

  // Fetch options for one level into `target`, guarded against stale
  // responses. While loading, the dropdown itself says "Chargement…" (no
  // layout jump). When the list has a single choice, pick it and continue
  // the cascade automatically.
  async _fetchInto(level, target, url, silent) {
    if (!target) return;
    const seq = ++this._seq[level];
    this._hideError();
    this._showLoadingIn(target);
    if (!silent) this._startLoading();

    try {
      const response = await fetch(url);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      if (seq !== this._seq[level]) return; // a newer choice took over
      if (!data || data.length === 0) console.warn("Empty options for", url);

      this._populate(target, data || []);
      target.disabled = false;

      if (!silent && data && data.length === 1 && !target.value) {
        target.value = String(data[0].id);
        target.dispatchEvent(new Event("change", { bubbles: true }));
      }
    } catch (error) {
      if (seq !== this._seq[level]) return;
      console.error("Failed to load", url, error);
      this._clear(target);
      if (!silent) this._showError();
    } finally {
      target.classList.remove("is-loading");
      if (!silent) this._endLoading();
    }
  }

  _showLoadingIn(target) {
    const text = (this.hasLoadingValue && this.loadingValue) || "…";
    target.innerHTML = `<option value="">${text}</option>`;
    target.disabled = true;
    target.classList.add("is-loading");
  }

  // Drop the server-saved selection so it isn't re-applied after the
  // citizen changes a parent level.
  _forgetSaved(...targets) {
    targets.forEach(t => { if (t) delete t.dataset.selected; });
  }
  _populate(target, items) {
    const currentValue = target.dataset.selected;
    target.innerHTML = `<option value="">${target.dataset.prompt || "Please select"}</option>`;

    items.forEach(({ id, name }) => {
      const option = document.createElement("option");
      option.value = id;
      option.textContent = name;
      if (id.toString() === currentValue) {
        option.selected = true;
        target.value = id;  // Ensure value sets post-populate
      }
      target.appendChild(option);
    });

    // If no match, but selected exists, set value (edge case)
    if (currentValue && !target.value) target.value = currentValue;
  }

  _clear(target) {
    if (target) {
      target.innerHTML = `<option value="">${target.dataset.prompt || "Please select"}</option>`;
      target.disabled = true;
      target.value = "";  // Clear value too
    }
  }

  _clearPostal() {
    if (this.hasPostalCodeTarget) this.postalCodeTarget.value = "";
  }

  _startLoading() {
    if (this.hasSpinnerTarget) this.spinnerTarget.classList.remove("d-none");
  }

  _endLoading() {
    if (this.hasSpinnerTarget) this.spinnerTarget.classList.add("d-none");
  }

  _showError() {
    if (this.hasErrorTarget) this.errorTarget.classList.remove("d-none");
  }

  _hideError() {
    if (this.hasErrorTarget) this.errorTarget.classList.add("d-none");
  }

  _disableAllExcept(...enabledTargets) {
    // Build targets array safely - only include targets that exist
    const targets = [];
    if (this.hasArrondissementTarget) targets.push(this.arrondissementTarget);
    if (this.hasCommuneTarget) targets.push(this.communeTarget);
    if (this.hasSectionTarget) targets.push(this.sectionTarget);

    targets.forEach(t => {
      if (t && !enabledTargets.includes(t)) t.disabled = true;
    });
  }
}