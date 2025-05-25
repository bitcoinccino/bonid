import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="confirmation"
export default class extends Controller {
  static targets = ["checkbox"]

  validate(event) {
    if (!this.checkboxTarget.checked) {
      event.preventDefault()
      this.checkboxTarget.setCustomValidity("You must agree before proceeding.")
      this.checkboxTarget.reportValidity()
    } else {
      this.checkboxTarget.setCustomValidity("")
    }
  }
}
