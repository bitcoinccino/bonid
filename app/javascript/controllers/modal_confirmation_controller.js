// app/javascript/controllers/modal_confirmation_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    title: String,
    body: String,
    action: String,
    method: String
  }

  connect() {
    console.log("✅ modal-confirmation connected")
    this.modal = new bootstrap.Modal(document.getElementById("confirmationModal"))
  }

  open(event) {
    event.preventDefault()
    console.log("✅ modal-confirmation#open fired")

    document.getElementById("confirmationModalTitle").textContent = this.titleValue
    document.getElementById("confirmationModalBody").textContent = this.bodyValue

    const form = document.getElementById("confirmationModalForm")
    form.action = this.actionValue
    form.method = this.methodValue.toLowerCase() === "get" ? "get" : "post"
    document.getElementById("confirmationModalMethodInput").value = this.methodValue.toUpperCase()

    this.modal.show()
  }
}
