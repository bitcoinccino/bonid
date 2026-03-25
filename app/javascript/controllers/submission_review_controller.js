// app/javascript/controllers/submission_review_controller.js
//
// Stimulus controller for the citizen identity submission review step.
//
// Responsibilities:
//   - Populate review summary when entering the review step (last step)
//   - Confirmation checkbox → submit button toggle
//
// Pattern: Same as complaint_form_controller.js review logic.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "reviewId",
    "reviewSelfie",
    "reviewSupporting",
    "reviewSignature",
    "submitButton",
    "confirmCheckbox"
  ]

  connect() {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = true
    }
  }

  // Called via: data-action="wizard:stepChanged->submission-review#onStepChanged"
  onStepChanged(event) {
    const step = event.detail?.step
    const totalSteps = this.element.querySelectorAll("[data-wizard-target='step']").length
    if (step === totalSteps) {
      this.populateReview()
    }
  }

  populateReview() {
    const form = this.element

    // ── 1. Government ID ──
    if (this.hasReviewIdTarget) {
      const idType = this._selectedText(form, "identity_submission[id_type]") ||
                     this._fieldValue(form, "identity_submission[id_type]")

      const cinFront = this._fileLabel(form, "identity_submission[cin_front]")
      const cinBack  = this._fileLabel(form, "identity_submission[cin_back]")
      const passport = this._fileLabel(form, "identity_submission[passport]")

      let docsHtml = ""
      if (idType.toLowerCase().includes("cin")) {
        docsHtml = `
          <div class="col-sm-6"><strong>CIN Front:</strong> ${cinFront}</div>
          <div class="col-sm-6"><strong>CIN Back:</strong> ${cinBack}</div>
        `
      } else {
        docsHtml = `
          <div class="col-sm-6"><strong>Passport:</strong> ${passport}</div>
        `
      }

      this.reviewIdTarget.innerHTML = `
        <div class="row g-2" style="font-size:0.82rem;">
          <div class="col-12"><strong>ID Type:</strong> ${this._esc(idType) || "—"}</div>
          ${docsHtml}
        </div>
      `
    }

    // ── 2. Face Liveness Check ──
    // Skip JS population if server already rendered reused content (skip_liveness)
    if (this.hasReviewSelfieTarget && !this.reviewSelfieTarget.querySelector("[data-reused]")) {
      const selfieInput = form.querySelector("input[name='identity_submission[selfie]']")
      const hasSelfie = selfieInput?.files?.length > 0 ||
                        (selfieInput?.type === "hidden" && selfieInput?.value?.length > 0)

      // Also check if the liveness detector reported success (even if blob is missing)
      const livenessController = form.querySelector("[data-controller='liveness-detector']")
      const livenessPassed = livenessController?.dataset?.livenessDetectorPassedValue === "true"

      const passed = hasSelfie || livenessPassed
      const statusText = passed ? "Verified" : "Not completed"
      const statusClass = passed ? "text-success" : "text-danger"
      const statusIcon = passed ? "checkbox-circle" : "close-circle"

      this.reviewSelfieTarget.innerHTML = `
        <div style="font-size:0.82rem;">
          <strong>Face Liveness:</strong>
          <span class="${statusClass}">
            <i class="ri-${statusIcon}-line me-1"></i>${statusText}
          </span>
        </div>
      `
    }

    // ── 3. Supporting Document ──
    if (this.hasReviewSupportingTarget) {
      const docType = this._selectedText(form, "identity_submission[additional_proof_type]") ||
                      this._fieldValue(form, "identity_submission[additional_proof_type]")
      const docFile = this._fileLabel(form, "identity_submission[additional_proof]")

      this.reviewSupportingTarget.innerHTML = `
        <div class="row g-2" style="font-size:0.82rem;">
          <div class="col-sm-6"><strong>Document Type:</strong> ${this._esc(docType) || "—"}</div>
          <div class="col-sm-6"><strong>File:</strong> ${docFile}</div>
        </div>
      `
    }

    // ── 4. Signature ──
    // Skip JS population if server already rendered reused content (skip_signature)
    if (this.hasReviewSignatureTarget && !this.reviewSignatureTarget.querySelector("[data-reused]")) {
      const sigFile = this._fileLabel(form, "identity_submission[signature]")
      const drawnInput = form.querySelector("input[name='identity_submission[signature_drawn]']")
      const hasDrawn = drawnInput?.value?.length > 100 // base64 data

      let sigStatus
      if (hasDrawn) {
        sigStatus = '<span class="text-success"><i class="ri-checkbox-circle-line me-1"></i>Drawn on canvas</span>'
      } else if (sigFile !== "Not uploaded") {
        sigStatus = `<span class="text-success"><i class="ri-checkbox-circle-line me-1"></i>${sigFile}</span>`
      } else {
        sigStatus = '<span class="text-danger"><i class="ri-close-circle-line me-1"></i>Not provided</span>'
      }

      this.reviewSignatureTarget.innerHTML = `
        <div style="font-size:0.82rem;">
          <strong>Signature:</strong> ${sigStatus}
        </div>
      `
    }
  }

  // ── Confirmation checkbox → submit toggle ──

  toggleSubmit() {
    if (!this.hasSubmitButtonTarget || !this.hasConfirmCheckboxTarget) return
    this.submitButtonTarget.disabled = !this.confirmCheckboxTarget.checked
  }

  // ── Private Helpers ──

  _fieldValue(form, name) {
    const el = form.querySelector(`[name="${name}"]`)
    return el?.value?.trim() || ""
  }

  _selectedText(form, name) {
    const el = form.querySelector(`select[name="${name}"]`)
    if (!el || el.selectedIndex < 0) return ""
    const opt = el.options[el.selectedIndex]
    return (opt && opt.value) ? opt.text.trim() : ""
  }

  _fileLabel(form, name) {
    const input = form.querySelector(`input[name="${name}"]`)
    if (!input || !input.files || input.files.length === 0) return "Not uploaded"
    return this._esc(input.files[0].name)
  }

  _esc(str) {
    if (!str) return ""
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }
}
