import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["idType", "cinFields", "passportField"];

  connect() {
    this.toggle(); // Ensures correct state on load
  }

  toggle() {
    const idType = this.idTypeTarget.value;
    const showCIN = idType === "cin";

    this.cinFieldsTarget.classList.toggle("d-none", !showCIN);
    this.passportFieldTarget.classList.toggle("d-none", showCIN);
  }
}
