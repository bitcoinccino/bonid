// app/javascript/controllers/reason_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["select", "textareaWrapper", "textarea"];

  connect() {
    this.toggle(); // run on load
  }

  toggle() {
    const value = this.selectTarget.value;
    const normalized = value?.toLowerCase();

    // show textarea if "Other" is selected
    this.textareaWrapperTarget.style.display = normalized === "other" ? "block" : "none";
    this.textareaTarget.required = normalized === "other";

    if (normalized !== "other") {
      this.textareaTarget.value = "";
    }
  }
}
