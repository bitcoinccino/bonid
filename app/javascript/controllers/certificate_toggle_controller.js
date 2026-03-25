import { Controller } from "@hotwired/stimulus"

/*
  Certificate Toggle Controller
  -----------------------------
  Targets:
    - card
    - qr
*/

export default class extends Controller {
  static targets = ["card", "qr"]

  static values = {
    active: String
  }

  connect() {
    // default state
    this.show("card")
  }

  showCard() {
    this.show("card")
  }

  showQR() {
    this.show("qr")
  }

  show(view) {
    // toggle views
    this.cardTarget.classList.toggle("active", view === "card")
    this.qrTarget.classList.toggle("active", view === "qr")

    // toggle buttons
    this.element
      .querySelectorAll(".certificate-toggle")
      .forEach(btn => {
        btn.classList.toggle(
          "active",
          btn.dataset.view === view
        )
      })

    // move background slider
    const wrapper = this.element.querySelector(".certificate-toggle-wrapper")
    if (wrapper) wrapper.dataset.active = view

    this.activeValue = view
  }
}
