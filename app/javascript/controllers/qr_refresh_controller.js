import { Controller } from "@hotwired/stimulus"

// Spinner + disable button during Turbo form submit, then reset after response
export default class extends Controller {
  static targets = ["spinner", "submit", "label", "icon"]

  connect() {
    this.reset()
  }

  start() {
    // turbo:submit-start
    if (this.hasSpinnerTarget) this.spinnerTarget.classList.remove("d-none")
    if (this.hasIconTarget) this.iconTarget.classList.add("d-none")
    if (this.hasSubmitTarget) this.submitTarget.disabled = true
    if (this.hasLabelTarget) this.labelTarget.textContent = "Refreshing..."
  }

  finish() {
    // turbo:submit-end
    this.reset()
  }

  reset() {
    if (this.hasSpinnerTarget) this.spinnerTarget.classList.add("d-none")
    if (this.hasIconTarget) this.iconTarget.classList.remove("d-none")
    if (this.hasSubmitTarget) this.submitTarget.disabled = false
    if (this.hasLabelTarget) this.labelTarget.textContent = "Refresh Now"
  }
}
