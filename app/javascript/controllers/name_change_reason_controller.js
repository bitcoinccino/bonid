import { Controller } from "@hotwired/stimulus"

// Toggles the "Other Reason" text field visibility based on the reason dropdown
export default class extends Controller {
  static targets = ["reason", "otherField"]

  toggle() {
    const isOther = this.reasonTarget.value === "other"
    this.otherFieldTarget.style.display = isOther ? "" : "none"
  }
}
