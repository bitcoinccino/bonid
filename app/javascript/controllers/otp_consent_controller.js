import { Controller } from "@hotwired/stimulus"

// Controls OTP input behavior for transaction consent approve/deny modals
export default class extends Controller {
  static targets = ["input", "decisionInput", "approveBtn", "denyBtn", "countdown", "modalTitle"]
  static values  = { expiresAt: String }

  connect() {
    this.submitting = false
    this.expired = false
    this.activeDecision = null // locked to "approve" or "deny" by card button

    // Detect which card button opened the modal and lock to that action
    this.element.addEventListener("shown.bs.modal", (event) => {
      const trigger = event.relatedTarget
      if (trigger?.hasAttribute("data-deny")) {
        this.activeDecision = "deny"
      } else {
        this.activeDecision = "approve"
      }
      this.resetForm()
    })

    // Re-enable buttons after Turbo response (success or error)
    this.boundHandleSubmitEnd = this.handleSubmitEnd.bind(this)
    document.addEventListener("turbo:submit-end", this.boundHandleSubmitEnd)

    // Handle Turbo fetch errors (network failures, timeouts)
    this.boundHandleFetchError = this.handleFetchError.bind(this)
    document.addEventListener("turbo:fetch-request-error", this.boundHandleFetchError)

    // Start countdown if expiry is set
    if (this.hasExpiresAtValue && this.hasCountdownTarget) {
      this.startCountdown()
    }
  }

  disconnect() {
    if (this.timer) clearInterval(this.timer)
    document.removeEventListener("turbo:submit-end", this.boundHandleSubmitEnd)
    document.removeEventListener("turbo:fetch-request-error", this.boundHandleFetchError)
  }

  // Re-enable buttons after Turbo response
  handleSubmitEnd(event) {
    // Only handle events from forms inside this modal
    if (!this.element.contains(event.target)) return

    this.submitting = false
    const success = event.detail?.success

    if (success) {
      // Close modal on successful decision
      try {
        const modal = bootstrap.Modal.getInstance(this.element)
        if (modal) modal.hide()
      } catch (e) { /* modal may already be gone */ }
    } else {
      // Re-enable buttons so citizen can retry
      this.resetButtonLabels()
      this.updateButtons()
    }
  }

  // Handle network failures gracefully
  handleFetchError(event) {
    if (!this.element.contains(event.target)) return

    this.submitting = false
    this.resetButtonLabels()
    this.updateButtons()
    this.showError("Network error. Please check your connection and try again.")
  }

  // Validate and filter OTP input — digits only, max 6
  onInput() {
    const val = this.inputTarget.value.replace(/\D/g, "").slice(0, 6)
    this.inputTarget.value = val
    this.clearError()
    this.updateButtons()
  }

  // Paste handler — auto-extract 6-digit code from pasted text
  onPaste(event) {
    event.preventDefault()
    const pasted = (event.clipboardData || window.clipboardData).getData("text")
    const digits = pasted.replace(/\D/g, "").slice(0, 6)
    this.inputTarget.value = digits
    this.clearError()
    this.updateButtons()
  }

  updateButtons() {
    const ready = this.inputTarget.value.length === 6 && !this.submitting && !this.expired

    // Only enable the button that matches the active decision
    if (this.hasApproveBtnTarget) {
      this.approveBtnTarget.disabled = !(ready && this.activeDecision === "approve")
    }
    if (this.hasDenyBtnTarget) {
      this.denyBtnTarget.disabled = !(ready && this.activeDecision === "deny")
    }
  }

  // Single submit method — always uses the locked activeDecision
  submit() {
    this.setDecisionAndSubmit(this.activeDecision)
  }

  approve() { this.setDecisionAndSubmit("approve") }
  deny()    { this.setDecisionAndSubmit("deny") }

  setDecisionAndSubmit(decision) {
    if (this.submitting || this.expired) return

    // Guard: only allow valid decisions
    if (decision !== "approve" && decision !== "deny") return

    // Safety: decision must match what the card button intended
    if (this.activeDecision && decision !== this.activeDecision) {
      this.showError("Something went wrong. Please close and try again.")
      return
    }

    // Client-side validation before submitting
    const otp = this.inputTarget.value
    if (otp.length !== 6) {
      this.shakeInput()
      this.showError("Please enter all 6 digits.")
      return
    }
    if (!/^\d{6}$/.test(otp)) {
      this.shakeInput()
      this.showError("Code must be digits only.")
      return
    }

    this.submitting = true

    // Set the decision FIRST via Stimulus target (reliable)
    if (this.hasDecisionInputTarget) {
      this.decisionInputTarget.value = decision
    }

    const form = this.element.querySelector("form")
    if (!form) { this.submitting = false; return }

    // Double-check: also set via DOM query as fallback
    const decisionField = form.querySelector('input[name="decision"]')
    if (decisionField) decisionField.value = decision

    // Final safety check — abort if decision wasn't set
    const actualValue = decisionField?.value || this.decisionInputTarget?.value
    if (actualValue !== decision) {
      this.submitting = false
      this.showError("Something went wrong. Please try again.")
      return
    }

    // Show loading state on the active button only
    if (decision === "approve" && this.hasApproveBtnTarget) {
      this.approveBtnTarget.disabled = true
      this.approveBtnTarget.innerHTML = '<i class="ri-loader-4-line ri-spin me-1"></i>Approving...'
    }
    if (decision === "deny" && this.hasDenyBtnTarget) {
      this.denyBtnTarget.disabled = true
      this.denyBtnTarget.innerHTML = '<i class="ri-loader-4-line ri-spin me-1"></i>Denying...'
    }

    // Disable input during submission
    this.inputTarget.readOnly = true

    form.requestSubmit()
  }

  // Countdown timer
  startCountdown() {
    const expiresAt = new Date(this.expiresAtValue).getTime()

    // Check if already expired on load
    if (expiresAt <= Date.now()) {
      this.markExpired()
      return
    }

    this.updateCountdown(expiresAt)
    this.timer = setInterval(() => this.updateCountdown(expiresAt), 1000)
  }

  updateCountdown(expiresAt) {
    const diff = expiresAt - Date.now()

    if (diff <= 0) {
      clearInterval(this.timer)
      this.markExpired()
      return
    }

    const mins = Math.floor(diff / 60000)
    const secs = Math.floor((diff % 60000) / 1000)
    this.countdownTarget.textContent = `${mins}:${secs.toString().padStart(2, "0")} remaining`

    if (mins < 2) {
      this.countdownTarget.classList.add("text-danger", "fw-bold")
    } else {
      this.countdownTarget.classList.remove("text-danger", "fw-bold")
    }
  }

  // Centralized expiry handling
  markExpired() {
    this.expired = true
    if (this.hasCountdownTarget) {
      this.countdownTarget.textContent = "Expired"
      this.countdownTarget.classList.add("text-danger", "fw-bold")
    }
    if (this.hasApproveBtnTarget) this.approveBtnTarget.disabled = true
    if (this.hasDenyBtnTarget)    this.denyBtnTarget.disabled = true
    if (this.hasInputTarget)      this.inputTarget.disabled = true

    this.showError("This request has expired. Please close this window.")
  }

  // Show inline error in the modal's error placeholder
  showError(message) {
    const errorEl = this.element.querySelector("[id^='otp-error-']")
    if (errorEl) {
      errorEl.innerHTML = `<div class="alert alert-danger border-0 rounded-3 py-2 px-3 small mb-0">${this.escapeHtml(message)}</div>`
    }
  }

  // Clear inline error when citizen starts re-typing
  clearError() {
    const errorEl = this.element.querySelector("[id^='otp-error-']")
    if (errorEl) errorEl.innerHTML = ""
  }

  // Visual feedback — shake the input on invalid submission
  shakeInput() {
    this.inputTarget.classList.add("shake-error")
    this.inputTarget.addEventListener("animationend", () => {
      this.inputTarget.classList.remove("shake-error")
    }, { once: true })
  }

  // Escape HTML to prevent XSS in error messages
  escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }

  resetButtonLabels() {
    if (this.hasApproveBtnTarget) {
      this.approveBtnTarget.innerHTML = '<i class="ri-check-double-line me-1"></i>Approve Transaction'
    }
    if (this.hasDenyBtnTarget) {
      this.denyBtnTarget.innerHTML = '<i class="ri-close-circle-line me-1"></i>Deny Transaction'
    }
  }

  resetForm() {
    this.submitting = false
    if (this.hasInputTarget) {
      this.inputTarget.value = ""
      this.inputTarget.readOnly = false
      this.inputTarget.disabled = false
      this.inputTarget.focus()
    }

    // Pre-set decision based on which card button was clicked
    if (this.hasDecisionInputTarget) {
      this.decisionInputTarget.value = this.activeDecision || ""
    }

    this.clearError()
    this.resetButtonLabels()

    // Show ONLY the button matching the active decision
    if (this.activeDecision === "deny") {
      if (this.hasApproveBtnTarget) this.approveBtnTarget.classList.add("d-none")
      if (this.hasDenyBtnTarget)    this.denyBtnTarget.classList.remove("d-none")
    } else if (this.activeDecision === "approve") {
      if (this.hasApproveBtnTarget) this.approveBtnTarget.classList.remove("d-none")
      if (this.hasDenyBtnTarget)    this.denyBtnTarget.classList.add("d-none")
    } else {
      // Fallback: show both (shouldn't happen)
      if (this.hasApproveBtnTarget) this.approveBtnTarget.classList.remove("d-none")
      if (this.hasDenyBtnTarget)    this.denyBtnTarget.classList.remove("d-none")
    }

    this.updateButtons()
  }
}
