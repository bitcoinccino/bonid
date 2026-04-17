import { Controller } from "@hotwired/stimulus"

// BonID Citizen Wizard Controller
// Handles multi-step form navigation with validation, progress indicators,
// and step-change events for other controllers (e.g. complaint-form) to listen to.
export default class extends Controller {
  static targets = ["step", "progressBar", "stepIndicator", "stepTitle", "stepAlert"]
  static values = {
    currentStep: { type: Number, default: 1 },
    skipSteps:   { type: Array, default: [] }   // e.g. [2] or [2,3] — steps to auto-skip
  }

  connect() {
    // Restore step from sessionStorage on page refresh
    const key = this._storageKey()
    const saved = sessionStorage.getItem(key)
    if (saved) {
      const step = parseInt(saved, 10)
      if (step >= 1 && step <= this.stepTargets.length) {
        this.currentStepValue = step
      }
    }
    this.showCurrentStep()
    this.updateProgress()
  }

  disconnect() {
    // Clear stored step when leaving the page entirely
  }

  next(event) {
    event.preventDefault()

    const currentStep = this.stepTargets[this.currentStepValue - 1]
    const requiredFields = currentStep.querySelectorAll("input[required], select[required], textarea[required]")

    const invalid = Array.from(requiredFields).some(input => {
      if (input.type === "file") return input.files.length === 0
      if (input.type === "checkbox") return !input.checked
      return !input.value.trim()
    })

    if (invalid) {
      // Show a specific message if liveness verification is the blocker
      const selfieField = currentStep.querySelector("input[name*='[selfie]'][required]")
      if (selfieField && !selfieField.value.trim()) {
        this.flashError("Please complete the face verification before proceeding.")
      } else {
        this.flashError("Please complete all required fields before continuing.")
      }
      this.highlightInvalid(currentStep)
      return // ⛔ stop progression
    }

    if (this.currentStepValue < this.stepTargets.length) {
      this.currentStepValue++

      // Auto-skip forward: keep jumping while current step is in the skip list
      while (this._isSkipped(this.currentStepValue) && this.currentStepValue < this.stepTargets.length) {
        this.currentStepValue++
      }

      this.showCurrentStep()
      this.updateProgress()
      this.scrollToTop()
      this.dispatch("stepChanged", { detail: { step: this.currentStepValue } })
    }
  }

  previous(event) {
    event.preventDefault()
    if (this.currentStepValue > 1) {
      this.currentStepValue--

      // Auto-skip backward: keep jumping while current step is in the skip list
      while (this._isSkipped(this.currentStepValue) && this.currentStepValue > 1) {
        this.currentStepValue--
      }

      this.showCurrentStep()
      this.updateProgress()
      this.scrollToTop()
      this.dispatch("stepChanged", { detail: { step: this.currentStepValue } })
    }
  }

  // Jump directly to a specific step (used by Review "Edit" buttons)
  goToStep(event) {
    event.preventDefault()
    const step = parseInt(event.currentTarget.dataset.step, 10)

    // Prevent navigating to a skipped step
    if (this._isSkipped(step)) return

    if (step >= 1 && step <= this.stepTargets.length) {
      this.currentStepValue = step
      this.showCurrentStep()
      this.updateProgress()
      this.scrollToTop()
      this.dispatch("stepChanged", { detail: { step: this.currentStepValue } })
    }
  }

  showCurrentStep() {
    this.stepTargets.forEach((step, index) => {
      const active = index + 1 === this.currentStepValue
      step.classList.toggle("active", active)
      step.classList.toggle("d-none", !active)
      step.style.display = active ? "" : "none"
    })
    this.updateProgress()
    sessionStorage.setItem(this._storageKey(), this.currentStepValue)
  }

  updateProgress() {
    const total = this.stepTargets.length
    const progress = ((this.currentStepValue - 1) / (total - 1)) * 100
    if (this.hasProgressBarTarget)
      this.progressBarTarget.style.width = `${progress}%`

    this.stepIndicatorTargets.forEach((indicator, index) => {
      const circle = indicator.querySelector(".step-circle")
      if (!circle) return
      const stepNum   = index + 1
      const completed = stepNum < this.currentStepValue
      const active    = stepNum === this.currentStepValue
      const skipped   = this._isSkipped(stepNum)

      circle.classList.toggle("active", active)
      circle.classList.toggle("completed", completed || skipped) // Skipped step shows as completed ✓
    })

    this.stepTitleTargets.forEach((title, index) => {
      title.classList.toggle("d-none", index + 1 !== this.currentStepValue)
    })

    this.stepAlertTargets.forEach((alert, index) => {
      alert.classList.toggle("d-none", index + 1 !== this.currentStepValue)
    })
  }

  flashError(message) {
    const existing = document.querySelector(".wizard-alert")
    if (existing) existing.remove()

    const alert = document.createElement("div")
    alert.className = "alert alert-danger wizard-alert small mt-3"
    alert.innerHTML = `<i class="ri-error-warning-line me-1"></i>${message}`
    this.stepTargets[this.currentStepValue - 1].prepend(alert)
    setTimeout(() => alert.remove(), 4000)
  }

  highlightInvalid(step) {
    step.querySelectorAll("input[required], select[required], textarea[required]").forEach(field => {
      if (field.type === "checkbox" && !field.checked) field.classList.add("is-invalid")
      else if (!field.value && field.type !== "file" && field.type !== "checkbox") field.classList.add("is-invalid")
      else if (field.type === "file" && field.files.length === 0) field.classList.add("is-invalid")
    })
  }

  scrollToTop() {
    window.scrollTo({ top: 0, behavior: "smooth" })
  }

  _storageKey() {
    return `wizard-step:${window.location.pathname}`
  }

  // Check if a step number is in the skip list
  _isSkipped(stepNum) {
    return this.skipStepsValue.includes(stepNum)
  }
}
