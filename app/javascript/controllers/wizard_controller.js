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
    // Restore step from sessionStorage on page refresh. Defer one tick so
    // sibling controllers (notably wizard-persistence) finish restoring
    // localStorage values into the form before we check whether prior
    // required fields are populated.
    this._advancing = false
    const key = this._storageKey()
    const saved = sessionStorage.getItem(key)
    let restored = 1
    if (saved) {
      const step = parseInt(saved, 10)
      if (step >= 1 && step <= this.stepTargets.length) restored = step
    }
    this.currentStepValue = restored
    this.showCurrentStep()
    this.updateProgress()

    if (restored > 1) {
      setTimeout(() => {
        const firstIncomplete = this._firstIncompleteStep(restored - 1)
        if (firstIncomplete && firstIncomplete < restored) {
          // The restored step is ahead of where the citizen actually has
          // data — most often because they previously completed the wizard
          // (or signed up fresh in a tab whose sessionStorage still points
          // to a prior session's final step). Drop back to the first step
          // that actually needs input.
          this.currentStepValue = firstIncomplete
          this.showCurrentStep()
          this.updateProgress()
        }
      }, 60)
    }
  }

  disconnect() {
    // Clear stored step when leaving the page entirely
  }

  // Wipes the persisted step pointer. Wire to the form's submit action
  // (`submit->wizard#clear`) so a future fresh visit doesn't restore the
  // post-submit step number on a brand-new form.
  clear() {
    try { sessionStorage.removeItem(this._storageKey()) } catch (_) { /* disabled */ }
  }

  next(event) {
    event.preventDefault()

    // Re-entrancy guard: while a transition is in flight, ignore further
    // Continue clicks. The button is also disabled visually, but disabled
    // buttons can still receive clicks via dispatchEvent / programmatic
    // triggers, which would double-increment the step counter and skip
    // a step (e.g. Photo → Identité instead of Photo → Personnel).
    if (this._advancing) return
    this._advancing = true

    // Snapshot the step we're advancing FROM. Don't re-read currentStepValue
    // inside the setTimeout — anything that mutates it during the 450ms
    // window (a sibling controller, another action) would corrupt the jump.
    const fromStep = this.currentStepValue
    const stepEl = this.stepTargets[fromStep - 1]
    const button = event.currentTarget

    this._setButtonChecking(button)

    requestAnimationFrame(() => {
      const requiredFields = stepEl.querySelectorAll("input[required], select[required], textarea[required]")

      const invalid = Array.from(requiredFields).some(input => {
        // Skip required fields whose layout is hidden (display:none on the
        // field or any ancestor — id-switcher toggles CIN vs Passport this
        // way). Without this, marking both cin_back and passport required
        // would block users who selected the other type.
        if (input.offsetParent === null && input.type !== "hidden") return false
        if (input.type === "file") return input.files.length === 0
        if (input.type === "checkbox") return !input.checked
        return !input.value.trim()
      })

      if (invalid) {
        this._advancing = false
        this._restoreButton(button)
        const selfieField = stepEl.querySelector("input[name*='[selfie]'][required]")
        if (selfieField && !selfieField.value.trim()) {
          this.flashError("Please complete the face verification before proceeding.")
        } else {
          this.flashError("Please complete all required fields before continuing.")
        }
        this.highlightInvalid(stepEl)
        return
      }

      setTimeout(() => {
        this._restoreButton(button)

        // Compute the next step from the snapshotted fromStep, not from
        // the live currentStepValue. Then apply the skip-list ONLY if it's
        // explicitly populated (default is []), so empty skip-lists can't
        // accidentally consume a step via a stale closure.
        let target = fromStep + 1
        if (this.skipStepsValue.length > 0) {
          while (target < this.stepTargets.length && this._isSkipped(target)) {
            target++
          }
        }

        if (target > this.stepTargets.length) target = this.stepTargets.length

        this.currentStepValue = target
        this.showCurrentStep()
        this.updateProgress()
        this.scrollToTop()
        this.dispatch("stepChanged", { detail: { step: this.currentStepValue } })
        this._advancing = false
      }, 450)
    })
  }

  // Replaces the button's contents with a spinner + "Tcheke..." label and
  // disables it so the citizen can't double-click while we validate.
  _setButtonChecking(button) {
    if (!button || button.dataset.wizardOriginalHtml) return
    button.dataset.wizardOriginalHtml = button.innerHTML
    button.disabled = true
    button.style.opacity = "0.85"
    button.innerHTML = `<i class="ri-loader-4-line spin me-1"></i>Tcheke...`
  }

  _restoreButton(button) {
    if (!button || !button.dataset.wizardOriginalHtml) return
    button.innerHTML = button.dataset.wizardOriginalHtml
    button.disabled = false
    button.style.opacity = ""
    delete button.dataset.wizardOriginalHtml
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

  // Cross-step pre-submit validation. The Review step's submit button bypasses
  // wizard#next (it's a normal form submit), and goToStep lets citizens jump
  // around — both can land them on Review with an earlier step left
  // incomplete (e.g. they edited the ID, never re-confirmed Face Check, then
  // tapped Submit). Walk every step, find the first one with a missing
  // required field, jump back to it, and block the submit.
  //
  // Skipped steps (smart-resubmission carry-forward) are NOT validated since
  // their required fields are pre-populated server-side as hidden values.
  beforeSubmit(event) {
    for (let i = 0; i < this.stepTargets.length; i++) {
      const stepNum = i + 1
      if (this._isSkipped(stepNum)) continue

      const step = this.stepTargets[i]
      const requiredFields = step.querySelectorAll(
        "input[required], select[required], textarea[required]"
      )

      const invalid = Array.from(requiredFields).some(input => {
        if (input.offsetParent === null && input.type !== "hidden") return false
        if (input.type === "file")     return input.files.length === 0
        if (input.type === "checkbox") return !input.checked
        return !input.value.trim()
      })

      if (!invalid) continue

      event.preventDefault()
      event.stopPropagation()

      // Re-enable any submit buttons that turbo/Rails disabled on submit-click.
      this.element.querySelectorAll("[data-disable-with]").forEach(btn => {
        btn.disabled = false
      })

      // Jump to the offending step and surface the same error banner the
      // forward-navigation flow uses.
      this.currentStepValue = stepNum
      this.showCurrentStep()
      this.updateProgress()
      this.scrollToTop()
      this.dispatch("stepChanged", { detail: { step: stepNum } })

      const selfieField = step.querySelector("input[name*='[selfie]'][required]")
      if (selfieField && !selfieField.value.trim()) {
        this.flashError("Please complete the face verification before submitting.")
      } else {
        this.flashError(
          `Step ${stepNum} is incomplete. Please fill all required fields before submitting.`
        )
      }
      this.highlightInvalid(step)
      return
    }
    // All steps pass — let the form submit normally.
  }

  // Jump directly to a specific step (used by Review "Edit" buttons).
  // Backward jumps are always allowed (citizens fixing earlier data).
  // Forward jumps require all prior non-skipped required fields to be
  // filled — otherwise we bounce to the first incomplete step instead.
  goToStep(event) {
    event.preventDefault()
    const step = parseInt(event.currentTarget.dataset.step, 10)

    if (this._isSkipped(step)) return
    if (step < 1 || step > this.stepTargets.length) return

    if (step > this.currentStepValue) {
      const firstIncomplete = this._firstIncompleteStep(step - 1)
      if (firstIncomplete && firstIncomplete < step) {
        this.currentStepValue = firstIncomplete
        this.showCurrentStep()
        this.updateProgress()
        this.scrollToTop()
        this.dispatch("stepChanged", { detail: { step: firstIncomplete } })
        this.flashError(`Step ${firstIncomplete} is incomplete. Please fill all required fields before continuing.`)
        const targetStep = this.stepTargets[firstIncomplete - 1]
        this.highlightInvalid(targetStep)
        return
      }
    }

    this.currentStepValue = step
    this.showCurrentStep()
    this.updateProgress()
    this.scrollToTop()
    this.dispatch("stepChanged", { detail: { step: this.currentStepValue } })
  }

  showCurrentStep() {
    this.stepTargets.forEach((step, index) => {
      const active = index + 1 === this.currentStepValue
      step.classList.toggle("active", active)
      step.classList.toggle("d-none", !active)
      // Set display explicitly to "block" rather than "" — an empty string
      // resets the inline style but the server-rendered markup ships
      // `style="display:none"` on every non-photo step, and on some
      // browsers the empty assignment leaves the original computed value
      // until a reflow. Explicit "block" guarantees visibility.
      step.style.display = active ? "block" : "none"
      if (active) step.removeAttribute("hidden")
    })
    this.updateProgress()
    try { sessionStorage.setItem(this._storageKey(), this.currentStepValue) } catch (_) { /* disabled */ }
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

  // Returns the 1-based number of the first non-skipped step (within 1..maxStep)
  // that has at least one missing required field, or null if all are complete.
  // Used by goToStep + connect to keep citizens from skipping ahead with
  // empty earlier steps.
  _firstIncompleteStep(maxStep) {
    for (let i = 0; i < maxStep; i++) {
      const stepNum = i + 1
      if (this._isSkipped(stepNum)) continue

      const step = this.stepTargets[i]
      if (!step) continue

      const requiredFields = step.querySelectorAll(
        "input[required], select[required], textarea[required]"
      )
      const invalid = Array.from(requiredFields).some(input => {
        if (input.offsetParent === null && input.type !== "hidden") return false
        if (input.type === "file")     return input.files.length === 0
        if (input.type === "checkbox") return !input.checked
        return !input.value.trim()
      })
      if (invalid) return stepNum
    }
    return null
  }
}
