import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "textareaWrapper"]

  toggle() {
    const value = this.selectTarget.value
    this.textareaWrapperTarget.style.display = value === "other" ? "block" : "none"
  }
}

