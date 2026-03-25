// app/javascript/controllers/address_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "department", "arrondissement", "commune", "section", "postalCode",
    "spinner", "error"
  ];

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

    if (!silent) this._startLoading();
    this._clear(this.arrondissementTarget);
    this._clear(this.communeTarget);
    this._clear(this.sectionTarget);
    this._clearPostal();
    this._disableAllExcept(this.arrondissementTarget);

    if (!slug) {
      if (!silent) this._endLoading();
      console.warn("No slug for department:", departmentId);
      return;
    }

    try {
      const response = await fetch(`/departments/${slug}/arrondissements`);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      if (!data || data.length === 0) console.warn("Empty arrondissements for slug:", slug);
      this._populate(this.arrondissementTarget, data);
      this.arrondissementTarget.disabled = false;
    } catch (error) {
      console.error("Failed to load arrondissements:", error);
      if (!silent) this._showError();
    } finally {
      if (!silent) this._endLoading();
    }
  }

  // Load communes from arrondissement (4-level cascade)
  async loadCommunes(event, silent = false) {
    const id = event.target.value;

    if (!silent) this._startLoading();
    this._clear(this.communeTarget);
    this._clear(this.sectionTarget);
    this._clearPostal();
    this._disableAllExcept(this.communeTarget);

    if (!id) {
      if (!silent) this._endLoading();
      return;
    }

    try {
      const response = await fetch(`/arrondissements/${id}/communes`);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      if (!data || data.length === 0) console.warn("Empty communes for arrondissement:", id);
      this._populate(this.communeTarget, data);
      this.communeTarget.disabled = false;
    } catch (error) {
      console.error("Failed to load communes:", error);
      if (!silent) this._showError();
    } finally {
      if (!silent) this._endLoading();
    }
  }

  // Load communes directly from department (3-level cascade, skips arrondissement)
  async loadCommunesFromDepartment(event, silent = false) {
    const departmentId = event.target.value;

    if (!silent) this._startLoading();
    if (this.hasCommuneTarget) {
      this._clear(this.communeTarget);
      this.communeTarget.disabled = true;
    }
    if (this.hasSectionTarget) {
      this._clear(this.sectionTarget);
      this.sectionTarget.disabled = true;
    }
    this._clearPostal();

    if (!departmentId) {
      if (!silent) this._endLoading();
      return;
    }

    try {
      const response = await fetch(`/departments/${departmentId}/communes`);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      if (!data || data.length === 0) console.warn("Empty communes for department:", departmentId);
      if (this.hasCommuneTarget) {
        this._populate(this.communeTarget, data);
        this.communeTarget.disabled = false;
      }
    } catch (error) {
      console.error("Failed to load communes from department:", error);
      if (!silent) this._showError();
    } finally {
      if (!silent) this._endLoading();
    }
  }

  // Load sections from commune (alias for loadCommunalSections for consistency)
  async loadSections(event, silent = false) {
    return this.loadCommunalSections(event, silent);
  }

  async loadCommunalSections(event, silent = false) {
    const id = event.target.value;

    if (!silent) this._startLoading();
    if (this.hasSectionTarget) {
      this._clear(this.sectionTarget);
      this.sectionTarget.disabled = true;
    }
    this._clearPostal();

    if (!id) {
      if (!silent) this._endLoading();
      return;
    }

    try {
      const response = await fetch(`/communes/${id}/communal_sections`);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      if (!data || data.length === 0) console.warn("Empty sections for commune:", id);
      if (this.hasSectionTarget) {
        this._populate(this.sectionTarget, data);
        this.sectionTarget.disabled = false;
      }
    } catch (error) {
      console.error("Failed to load communal sections:", error);
      if (!silent) this._showError();
    } finally {
      if (!silent) this._endLoading();
    }
  }

  async loadPostalCode(event, silent = false) {
    // Skip if no postal code target
    if (!this.hasPostalCodeTarget) {
      console.log("ℹ️ No postal code target found - skipping postal code load");
      return;
    }

    const id = event.target.value;

    if (!silent) this._startLoading();
    this._clearPostal();

    if (!id) {
      if (!silent) this._endLoading();
      return;
    }

    try {
      const response = await fetch(`/communal_sections/${id}/postal_code`);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      this.postalCodeTarget.value = data.postal_code || "HT0000";
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