// app/javascript/controllers/modal_confirmation_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = {
    title: String,
    body: String,
    action: String,
    method: String
  }

  connect() {
    setTimeout(() => {
      const modalEl = document.getElementById("confirmationModal");
      if (modalEl) {
        this.modal = bootstrap.Modal.getOrCreateInstance(modalEl);
      } else {
        console.warn("⚠️ confirmationModal element not found.");
      }
    }, 50);
  }

  open(event) {
    event.preventDefault();
    console.log("✅ modal-confirmation#open");

    const titleEl = document.getElementById("confirmationModalTitle");
    const bodyEl = document.getElementById("confirmationModalBody");
    const formEl = document.getElementById("confirmationModalForm");
    const methodInput = document.getElementById("confirmationModalMethodInput");

    if (!titleEl || !bodyEl || !formEl || !methodInput || !this.modal) {
      console.error("❌ Missing modal elements or modal not initialized.");
      return;
    }

    titleEl.textContent = this.titleValue;
    bodyEl.textContent = this.bodyValue;
    formEl.action = this.actionValue;
    formEl.method = this.methodValue.toLowerCase() === "get" ? "get" : "post";
    methodInput.value = this.methodValue.toUpperCase();

    this.modal.show();
  }
}
