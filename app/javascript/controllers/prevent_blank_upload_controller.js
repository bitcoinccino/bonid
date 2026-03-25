// app/javascript/controllers/prevent_blank_upload_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.element.addEventListener("change", (e) => {
      if (!this.element.files.length) {
        this.element.disabled = true;
        this.element.form.requestSubmit(); // ensure Turbo processes properly
        this.element.disabled = false;
      }
    });
  }
}
