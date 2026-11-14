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

  // Localized copy from the page (citizen's portal language); each label
  // falls back to English.
  static values = { labels: Object }

  _l(key, fallback) {
    return (this.hasLabelsValue && this.labelsValue[key]) || fallback
  }

  // One review cell (same markup as _review_section.html.erb): small label
  // above the value. `valueHtml` is trusted (already escaped).
  _row(_cls, key, fallback, valueHtml) {
    return `<div class="review-item"><span class="review-label">${this._esc(this._l(key, fallback))}</span><span class="review-value">${valueHtml}</span></div>`
  }

  connect() {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = true
    }
    // Cache file names when users select files (iOS Safari clears file inputs in hidden steps)
    this._fileCache = {}
    this._attachFileCacheListeners()

    // If the wizard restored to the last step (e.g., after page re-render from validation error),
    // the stepChanged event won't fire — populate review immediately.
    requestAnimationFrame(() => this._populateIfOnReviewStep())
  }

  _populateIfOnReviewStep() {
    const steps = this.element.querySelectorAll("[data-wizard-target='step']")
    const totalSteps = steps.length
    if (totalSteps === 0) return

    // Find which step is currently active (visible)
    const activeStep = Array.from(steps).findIndex(s =>
      s.classList.contains("active") || !s.classList.contains("d-none")
    )
    if (activeStep + 1 === totalSteps) {
      this.populateReview()
    }
  }

  _attachFileCacheListeners() {
    const form = this.element
    const fileInputs = form.querySelectorAll("input[type='file']")
    fileInputs.forEach(input => {
      input.addEventListener("change", () => {
        if (input.files && input.files.length > 0) {
          this._fileCache[input.name] = input.files[0].name
        }
      })
    })
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
      const rawIdType = this._selectedText(form, "identity_submission[id_type]") ||
                        this._fieldValue(form, "identity_submission[id_type]")
      // Map raw values to human-readable labels
      const idTypeMap = { "cin": "CIN", "passport": this._l("passport", "Passport") }
      const idType = idTypeMap[rawIdType.toLowerCase()] || rawIdType

      const cinFront = this._fileLabel(form, "identity_submission[cin_front]")
      const cinBack  = this._fileLabel(form, "identity_submission[cin_back]")
      const passport = this._fileLabel(form, "identity_submission[passport]")

      let docsHtml = ""
      if (idType.toLowerCase().includes("cin")) {
        docsHtml = this._row("col-sm-6", "cin_front", "CIN Front", cinFront) +
                   this._row("col-sm-6", "cin_back", "CIN Back", cinBack)
      } else {
        docsHtml = this._row("col-sm-6", "passport", "Passport", passport)
      }

      this.reviewIdTarget.innerHTML =
        this._row("", "id_type", "ID Type", this._esc(idType) || this._todo()) + docsHtml
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
      const statusText = passed ? this._l("verified", "Verified") : this._l("not_completed", "Not completed")
      const statusClass = passed ? "text-success" : "text-danger"
      const statusIcon = passed ? "checkbox-circle" : "close-circle"

      this.reviewSelfieTarget.innerHTML = this._row("", "face_liveness", "Face check",
        `<span class="${statusClass}"><i class="ri-${statusIcon}-line me-1"></i>${this._esc(statusText)}</span>`)
    }

    // ── 3. Supporting Document ──
    if (this.hasReviewSupportingTarget) {
      // Prefer the picker's visible (localized) label over the stored value.
      const pickerDisplay = form.querySelector("[data-proof-picker-target='display']")
      const pickedValue = this._fieldValue(form, "identity_submission[additional_proof_type]")
      const docType = this._selectedText(form, "identity_submission[additional_proof_type]") ||
                      (pickedValue && pickerDisplay ? pickerDisplay.textContent.trim() : pickedValue)
      const docFile = this._fileLabel(form, "identity_submission[additional_proof]")

      this.reviewSupportingTarget.innerHTML =
        this._row("", "document_type", "Document type", this._esc(docType) || this._todo()) +
        this._row("", "file", "File", docFile)
    }

    // ── 4. Signature ──
    // Skip JS population if server already rendered reused content (skip_signature)
    if (this.hasReviewSignatureTarget && !this.reviewSignatureTarget.querySelector("[data-reused]")) {
      const sigFile = this._fileLabel(form, "identity_submission[signature]")
      const drawnInput = form.querySelector("input[name='identity_submission[signature_drawn]']")
      const hasDrawn = drawnInput?.value?.length > 100 // base64 data

      let sigStatus
      if (hasDrawn) {
        sigStatus = `<span class="text-success"><i class="ri-checkbox-circle-line me-1"></i>${this._esc(this._l("drawn", "Drawn on canvas"))}</span>`
      } else if (sigFile !== this._notUploaded()) {
        sigStatus = `<span class="text-success"><i class="ri-checkbox-circle-line me-1"></i>${sigFile}</span>`
      } else {
        sigStatus = `<span class="text-danger"><i class="ri-close-circle-line me-1"></i>${this._esc(this._l("not_provided", "Not provided"))}</span>`
      }

      this.reviewSignatureTarget.innerHTML = this._row("", "signature", "Signature", sigStatus)
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
    // Check live file input first
    if (input && input.files && input.files.length > 0) {
      return this._esc(input.files[0].name)
    }
    // Fall back to cached file name (iOS Safari clears file inputs in hidden steps)
    if (this._fileCache && this._fileCache[name]) {
      return this._esc(this._fileCache[name])
    }
    // Check for server-rendered "Uploaded" indicator (resubmission with existing attachment)
    if (input) {
      const container = input.closest(".col-md-6, .mb-3")
      const uploaded = container?.querySelector(".text-success")
      if (uploaded) return `<span class="text-success"><i class="ri-checkbox-circle-line me-1"></i>${this._esc(this._l("previously_uploaded", "Previously uploaded"))}</span>`
    }
    return this._notUploaded()
  }

  _notUploaded() {
    return this._esc(this._l("not_uploaded", "Not uploaded"))
  }

  _todo() {
    return `<span class="review-todo">${this._esc(this._l("not_provided", "Not provided"))}</span>`
  }

  _esc(str) {
    if (!str) return ""
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }
}
