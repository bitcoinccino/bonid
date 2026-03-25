import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="json-editor"
export default class extends Controller {
  static targets = []

  connect() {
    console.log("✅ JSON editor connected")
    this.textarea = this.element
    this.textarea.addEventListener("input", () => this.validateJSON())
  }

  validateJSON() {
    try {
      JSON.parse(this.textarea.value)
      this.textarea.classList.remove("is-invalid")
      this.removeAlert()
      return true
    } catch (e) {
      this.textarea.classList.add("is-invalid")
      this.showAlert("Invalid JSON: " + e.message)
      return false
    }
  }

  showAlert(message) {
    this.removeAlert()
    const alert = document.createElement("div")
    alert.className = "alert alert-danger mt-2 json-alert"
    alert.textContent = message
    this.textarea.parentNode.insertBefore(alert, this.textarea.nextSibling)
  }

  removeAlert() {
    const existing = this.textarea.parentNode.querySelector(".json-alert")
    if (existing) existing.remove()
  }
}
