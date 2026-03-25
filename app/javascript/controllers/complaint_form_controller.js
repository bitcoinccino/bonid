// app/javascript/controllers/complaint_form_controller.js
//
// Stimulus controller for the citizen officer complaint form.
//
// Responsibilities:
//   - Allegation category → Specific allegation cascade (Pillar 4)
//   - Witness BonID/BonTouris autofill — fetch, populate, reset (Pillar 5)
//   - Dynamic witness rows — add / remove
//   - Narrative character count (Pillar 5)
//   - Review step population (Step 6)
//   - Legal checkbox → submit button toggle
//
// NOTE: Department → Commune → Section cascade in Pillar 2 is handled by the
//       existing `address_controller.js` via `data-controller="address"` on
//       the Pillar 2 card-body. No loadCommunes needed here.

import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "specificSelect",      // Specific allegation <select> (Pillar 4)
    "witnessesContainer",  // Container div holding all witness rows (Pillar 5)
    "narrativeField",      // Narrative <textarea> (Pillar 5)
    "narrativeCount",      // Char count display span (Pillar 5)
    "submitButton",        // Submit button (Review step)
    "legalCheckbox",       // Legal declaration checkbox (Review step)
    // Review display targets
    "reviewComplainant",
    "reviewIncident",
    "reviewOfficer",
    "reviewAllegation",
    "reviewEvidence"
  ];

  // ─── Lifecycle ───────────────────────────────────────────────────────────

  connect() {
    if (this.hasNarrativeFieldTarget) {
      this._updateCount(this.narrativeFieldTarget.value.length);
    }
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = true;
    }
  }

  // ─── Pillar 4: Allegation category → Specific allegation ─────────────────

  updateSubcategories(event) {
    const category        = event.target.value;
    const allegationsJson = event.target.dataset.complaintFormAllegationsValue;

    if (!this.hasSpecificSelectTarget) return;

    this._resetSelect(this.specificSelectTarget, "Sélectionner d'abord la catégorie...");
    this.specificSelectTarget.disabled = true;

    if (!category || !allegationsJson) return;

    let allAllegations;
    try {
      allAllegations = JSON.parse(allegationsJson);
    } catch {
      console.error("[ComplaintForm] Could not parse allegations JSON");
      return;
    }

    const subcategories = allAllegations[category] || [];
    subcategories.forEach(sub => {
      const option       = document.createElement("option");
      option.value       = sub;
      option.textContent = sub;
      this.specificSelectTarget.appendChild(option);
    });

    this.specificSelectTarget.disabled = subcategories.length === 0;
  }

  // ─── Pillar 5: Narrative character count ─────────────────────────────────

  updateNarrativeCount(event) {
    this._updateCount(event.target.value.length);
  }

  // ─── Pillar 5: Witness BonID/BonTouris autofill ──────────────────────────

  async fetchWitness(event) {
    const input  = event.target;
    const row    = input.closest(".witness-row");
    if (!row) return;

    const rawValue = input.value.trim();
    const digits   = rawValue.replace(/\D/g, "");

    const feedback = row.querySelector(".witness-feedback");
    const spinner  = row.querySelector(".witness-spinner");

    this._clearFeedback(feedback, input);

    if (digits.length < 6) {
      this._showError(feedback, input, "Entrez au moins 6 chiffres (les 6 à 8 derniers de votre BonID ou BonTouris).");
      return;
    }

    // Show spinner
    if (spinner) spinner.classList.remove("d-none");
    input.disabled = true;

    try {
      const response = await fetch(
        `/citizens/officer_complaints/fetch_witness?q=${encodeURIComponent(digits)}`
      );
      const data = await response.json();

      if (spinner) spinner.classList.add("d-none");

      if (!response.ok || !data.success) {
        input.disabled = false;
        this._showError(feedback, input, data.error || "BonID introuvable. Vérifiez le numéro.");
        return;
      }

      // Populate and show the verified profile card
      this._fillWitnessProfile(row, data);
      this._showProfile(row);

    } catch (err) {
      console.error("[ComplaintForm] fetchWitness error:", err);
      if (spinner) spinner.classList.add("d-none");
      input.disabled = false;
      this._showError(feedback, input, "Erreur réseau. Veuillez réessayer.");
    }
  }

  resetWitness(event) {
    event.preventDefault();
    const row = event.target.closest(".witness-row");
    if (!row) return;

    // Clear all hidden fields
    row.querySelectorAll("input[type='hidden']").forEach(el => el.value = "");

    // Clear relation select
    const rel = row.querySelector("select[name*='[relation]']");
    if (rel) rel.value = "";

    // Re-show BonID input, hide profile
    const bonidField = row.querySelector(".witness-bonid-field");
    const profile    = row.querySelector(".witness-profile");
    const bonidInput = row.querySelector(".witness-bonid-input");
    const feedback   = row.querySelector(".witness-feedback");
    const spinner    = row.querySelector(".witness-spinner");

    if (profile)    profile.classList.add("d-none");
    if (bonidField) bonidField.classList.remove("d-none");
    if (bonidInput) {
      bonidInput.value    = "";
      bonidInput.disabled = false;
      bonidInput.classList.remove("is-valid", "is-invalid");
    }
    if (feedback) feedback.innerHTML = "";
    if (spinner)  spinner.classList.add("d-none");
  }

  // ─── Pillar 5: Witness rows — add / remove ───────────────────────────────

  addWitness(event) {
    event.preventDefault();
    if (!this.hasWitnessesContainerTarget) return;

    const template = this.witnessesContainerTarget.querySelector(".witness-row");
    if (!template) return;

    const clone = template.cloneNode(true);

    // Reset all inputs/selects/hidden fields in the clone
    clone.querySelectorAll("input").forEach(el => {
      el.value    = "";
      el.disabled = false;
      el.classList.remove("is-valid", "is-invalid");
    });
    clone.querySelectorAll("select").forEach(el => el.value = "");

    // Show bonid field, hide profile card in clone
    const bonidField = clone.querySelector(".witness-bonid-field");
    const profile    = clone.querySelector(".witness-profile");
    if (bonidField) bonidField.classList.remove("d-none");
    if (profile)    profile.classList.add("d-none");

    // Clear any feedback
    const feedback = clone.querySelector(".witness-feedback");
    if (feedback) feedback.innerHTML = "";

    // Reset photo/initials display
    const photo    = clone.querySelector(".witness-photo");
    const initials = clone.querySelector(".witness-initials");
    const name     = clone.querySelector(".witness-name-display");
    const bonidDsp = clone.querySelector(".witness-bonid-display");
    const badge    = clone.querySelector(".witness-type-badge");
    if (photo)    { photo.src = ""; photo.classList.add("d-none"); }
    if (initials) initials.textContent = "";
    if (name)     name.textContent = "";
    if (bonidDsp) bonidDsp.textContent = "";
    if (badge)    badge.textContent = "";

    this.witnessesContainerTarget.appendChild(clone);
    clone.scrollIntoView({ behavior: "smooth", block: "center" });
  }

  removeWitness(event) {
    event.preventDefault();
    if (!this.hasWitnessesContainerTarget) return;

    const rows = this.witnessesContainerTarget.querySelectorAll(".witness-row");
    if (rows.length <= 1) return; // Always keep at least one row

    const row = event.target.closest(".witness-row");
    if (row) row.remove();
  }

  // ─── Review Step: Populate summary ──────────────────────────────────────

  // Called when the wizard dispatches stepChanged — listens via:
  // data-action="wizard:stepChanged->complaint-form#onStepChanged"
  onStepChanged(event) {
    const step = event.detail?.step;
    const totalSteps = this.element.querySelectorAll("[data-wizard-target='step']").length;
    // Populate review when entering the last step (Review)
    if (step === totalSteps) {
      this.populateReview();
    }
  }

  populateReview() {
    const form = this.element;

    // ── 1. Complainant ──
    if (this.hasReviewComplainantTarget) {
      const name  = this._fieldValue(form, "officer_complaint[complainant_name]");
      const phone = this._fieldValue(form, "officer_complaint[complainant_phone]");
      const email = this._fieldValue(form, "officer_complaint[complainant_email]");
      const role  = this._selectedText(form, "officer_complaint[complainant_role]");

      this.reviewComplainantTarget.innerHTML = `
        <div class="row g-2" style="font-size:0.82rem;">
          <div class="col-sm-6"><strong>Nom:</strong> ${this._esc(name) || "—"}</div>
          <div class="col-sm-6"><strong>Téléphone:</strong> ${this._esc(phone) || "—"}</div>
          <div class="col-sm-6"><strong>Email:</strong> ${this._esc(email) || "—"}</div>
          <div class="col-sm-6"><strong>Rôle:</strong> ${this._esc(role) || "—"}</div>
        </div>
      `;
    }

    // ── 2. Incident Details ──
    if (this.hasReviewIncidentTarget) {
      const date    = this._fieldValue(form, "officer_complaint[occurred_at]");
      const dept    = this._selectedText(form, "officer_complaint[department_id]");
      const commune = this._selectedText(form, "officer_complaint[commune_id]");
      const section = this._selectedText(form, "officer_complaint[communal_section_id]");
      const locDesc = this._fieldValue(form, "officer_complaint[location_description]");
      const pnh     = this._selectedText(form, "officer_complaint[pnh_unit_involved]");

      const location = [dept, commune, section].filter(Boolean).join(" → ");

      this.reviewIncidentTarget.innerHTML = `
        <div class="row g-2" style="font-size:0.82rem;">
          <div class="col-sm-6"><strong>Date:</strong> ${this._esc(date) || "—"}</div>
          <div class="col-sm-6"><strong>Unité PNH:</strong> ${this._esc(pnh) || "—"}</div>
          <div class="col-12"><strong>Lieu:</strong> ${this._esc(location) || "—"}</div>
          <div class="col-12"><strong>Description du lieu:</strong> ${this._esc(locDesc) || "—"}</div>
        </div>
      `;
    }

    // ── 3. Officer Identification ──
    if (this.hasReviewOfficerTarget) {
      const badge   = this._fieldValue(form, "officer_complaint[accused_officer_badge]");
      const name    = this._fieldValue(form, "officer_complaint[accused_officer_name]");
      const vehicle = this._fieldValue(form, "officer_complaint[accused_officer_vehicle]");
      const unit    = this._selectedText(form, "officer_complaint[accused_officer_unit]");
      const physic  = this._fieldValue(form, "officer_complaint[physical_description]");

      this.reviewOfficerTarget.innerHTML = `
        <div class="row g-2" style="font-size:0.82rem;">
          <div class="col-sm-6"><strong>Badge:</strong> ${this._esc(badge) || "—"}</div>
          <div class="col-sm-6"><strong>Nom:</strong> ${this._esc(name) || "—"}</div>
          <div class="col-sm-6"><strong>Véhicule:</strong> ${this._esc(vehicle) || "—"}</div>
          <div class="col-sm-6"><strong>Unité:</strong> ${this._esc(unit) || "—"}</div>
          <div class="col-12"><strong>Description physique:</strong> ${this._esc(physic) || "—"}</div>
        </div>
      `;
    }

    // ── 4. Allegations ──
    if (this.hasReviewAllegationTarget) {
      const category = this._selectedText(form, "officer_complaint[allegation_category]");
      const specific = this._selectedText(form, "officer_complaint[specific_allegation]");

      this.reviewAllegationTarget.innerHTML = `
        <div class="row g-2" style="font-size:0.82rem;">
          <div class="col-sm-6"><strong>Catégorie:</strong> ${this._esc(category) || "—"}</div>
          <div class="col-sm-6"><strong>Acte spécifique:</strong> ${this._esc(specific) || "—"}</div>
        </div>
      `;
    }

    // ── 5. Evidence & Narrative ──
    if (this.hasReviewEvidenceTarget) {
      const narrative = this._fieldValue(form, "officer_complaint[narrative]");
      const truncated = narrative.length > 200 ? narrative.substring(0, 200) + "…" : narrative;

      // Count evidence files
      const fileInput = form.querySelector("input[name='officer_complaint[evidences][]']");
      const fileCount = fileInput?.files?.length || 0;

      // Collect witnesses
      const witnessNames = [];
      form.querySelectorAll(".witness-name-value").forEach(el => {
        if (el.value.trim()) witnessNames.push(el.value.trim());
      });
      const witnessText = witnessNames.length > 0
        ? witnessNames.join(", ")
        : "Aucun témoin ajouté";

      this.reviewEvidenceTarget.innerHTML = `
        <div style="font-size:0.82rem;">
          <div class="mb-2"><strong>Déclaration:</strong><br>
            <span style="color:#475467;">${this._esc(truncated) || "—"}</span>
          </div>
          <div class="mb-2"><strong>Pièces jointes:</strong> ${fileCount} fichier${fileCount !== 1 ? "s" : ""}</div>
          <div><strong>Témoins:</strong> ${this._esc(witnessText)}</div>
        </div>
      `;
    }
  }

  // ─── Review Step: Legal checkbox → Submit toggle ────────────────────────

  toggleSubmit() {
    if (!this.hasSubmitButtonTarget || !this.hasLegalCheckboxTarget) return;
    this.submitButtonTarget.disabled = !this.legalCheckboxTarget.checked;
  }

  // ─── Private Helpers ──────────────────────────────────────────────────────

  _updateCount(length) {
    if (!this.hasNarrativeCountTarget) return;
    this.narrativeCountTarget.textContent = `${length} caractère${length !== 1 ? "s" : ""}`;
    this.narrativeCountTarget.style.color = length < 50 ? "#dc3545" : "var(--mid-gray)";
  }

  _resetSelect(selectEl, promptText) {
    selectEl.innerHTML = `<option value="">${promptText}</option>`;
  }

  _clearFeedback(feedback, input) {
    if (feedback) feedback.innerHTML = "";
    if (input)    input.classList.remove("is-valid", "is-invalid");
  }

  _showError(feedback, input, message) {
    if (input)    input.classList.add("is-invalid");
    if (feedback) feedback.innerHTML = `<span class="text-danger"><i class="ri-error-warning-line me-1"></i>${message}</span>`;
  }

  _fillWitnessProfile(row, data) {
    // Hidden fields
    const set = (cls, val) => {
      const el = row.querySelector(cls);
      if (el) el.value = val || "";
    };
    set(".witness-bonid-value",   data.bonid);
    set(".witness-name-value",    data.name);
    set(".witness-phone-value",   data.phone);
    set(".witness-email-value",   data.email);
    set(".witness-id-type-value", data.id_type);

    // Display name + BonID
    const nameDisplay  = row.querySelector(".witness-name-display");
    const bonidDisplay = row.querySelector(".witness-bonid-display");
    const typeBadge    = row.querySelector(".witness-type-badge");
    if (nameDisplay)  nameDisplay.textContent  = data.name || "";
    if (bonidDisplay) bonidDisplay.textContent = data.bonid || "";
    if (typeBadge) {
      typeBadge.textContent  = data.id_type === "tourist" ? "BonTouris" : "BonID";
      typeBadge.style.cssText = `
        padding: 1px 6px; border-radius: 10px; font-size: 0.62rem; font-weight: 600;
        background: ${data.id_type === "tourist" ? "rgba(13,110,253,0.12)" : "rgba(25,135,84,0.12)"};
        color: ${data.id_type === "tourist" ? "#0d6efd" : "#198754"};
      `;
    }

    // Photo or initials
    const photo    = row.querySelector(".witness-photo");
    const initials = row.querySelector(".witness-initials");
    if (data.photo_url && photo) {
      photo.src = data.photo_url;
      photo.classList.remove("d-none");
      if (initials) initials.classList.add("d-none");
    } else if (initials) {
      const parts = (data.name || "?").split(" ");
      initials.textContent = parts.map(p => p[0]).slice(0, 2).join("").toUpperCase();
      initials.classList.remove("d-none");
      if (photo) photo.classList.add("d-none");
    }
  }

  _showProfile(row) {
    const bonidField = row.querySelector(".witness-bonid-field");
    const profile    = row.querySelector(".witness-profile");
    if (bonidField) bonidField.classList.add("d-none");
    if (profile)    profile.classList.remove("d-none");
  }

  // Get value of a form field by name
  _fieldValue(form, name) {
    const el = form.querySelector(`[name="${name}"]`);
    return el?.value?.trim() || "";
  }

  // Get selected option text of a select by name
  _selectedText(form, name) {
    const el = form.querySelector(`select[name="${name}"]`);
    if (!el || el.selectedIndex < 0) return "";
    const opt = el.options[el.selectedIndex];
    return (opt && opt.value) ? opt.text.trim() : "";
  }

  // Escape HTML to prevent XSS
  _esc(str) {
    if (!str) return "";
    const div = document.createElement("div");
    div.textContent = str;
    return div.innerHTML;
  }
}
