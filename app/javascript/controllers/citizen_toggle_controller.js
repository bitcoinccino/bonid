import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["pill", "bonidBtn", "qrBtn", "bonidCard", "qrCard"]

  connect() {
    // Wait for Turbo to render partials
    requestAnimationFrame(() => {
      if (this.hasBonidCardTarget && this.hasQrCardTarget) {
        this.showBonid()
      }
    })
  }

  showBonid() {
    // Move pill left
    this.pillTarget.style.transform = "translateX(0%)"

    // Update buttons
    this.bonidBtnTarget.classList.add("active")
    this.qrBtnTarget.classList.remove("active")

    // Show BonID card, hide QR card
    this.bonidCardTarget.classList.remove("d-none")
    this.qrCardTarget.classList.add("d-none")
  }

  showQr() {
    // Move pill right
    this.pillTarget.style.transform = "translateX(100%)"

    // Update buttons
    this.qrBtnTarget.classList.add("active")
    this.bonidBtnTarget.classList.remove("active")

    // Show QR card, hide BonID card
    this.qrCardTarget.classList.remove("d-none")
    this.bonidCardTarget.classList.add("d-none")
  }
}