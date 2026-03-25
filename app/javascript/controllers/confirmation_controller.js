// app/javascript/controllers/confirmation_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "body"]

  connect() {
    document.addEventListener("show.bs.modal", (event) => {
      const button = event.relatedTarget
      const modal = document.getElementById("confirmationModal")

      if (!button || !modal) return

      const form = modal.querySelector("#confirmationModalForm")
      const body = modal.querySelector("#confirmationModalBody")
      const methodInput = modal.querySelector("#confirmationModalMethodInput")

      // Update form action + method dynamically
      form.action = button.getAttribute("data-action-url")
      methodInput.value = button.getAttribute("data-action-method") || "patch"

      // Update message
      body.textContent = button.getAttribute("data-confirm-message") || "Are you sure?"
    })
  }
}
