// app/javascript/controllers/confirmation_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["checkbox"];

  validate(event) {
    if (!this.checkboxTarget.checked) {
      event.preventDefault();
      this.checkboxTarget.classList.add("is-invalid");
    } else {
      this.checkboxTarget.classList.remove("is-invalid");
    }
  }
}

