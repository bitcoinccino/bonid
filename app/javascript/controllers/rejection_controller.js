// app/javascript/controllers/rejection_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["reasonSelect", "commentsWrapper", "commentsField"]

  connect() {
    this.boundToggle = this.toggle.bind(this)
    this.modal = this.element.closest(".modal")

    if (this.modal) {
      this.modal.addEventListener("shown.bs.modal", this.boundToggle)
    }

    // Run immediately in case modal opens with "other" pre-selected
    this.toggle()
  }

  disconnect() {
    if (this.modal && this.boundToggle) {
      this.modal.removeEventListener("shown.bs.modal", this.boundToggle)
    }
  }

  toggle() {
    const value = this.reasonSelectTarget.value

    if (value === "other") {
      this.commentsWrapperTarget.classList.remove("d-none")
      this.commentsFieldTarget.required = true
      setTimeout(() => this.commentsFieldTarget.focus(), 150) // smooth
    } else {
      this.commentsWrapperTarget.classList.add("d-none")
      this.commentsFieldTarget.required = false
      this.commentsFieldTarget.value = ""
    }
  }
}