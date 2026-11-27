// app/javascript/controllers/qr_modal_controller.js
import { Controller } from "@hotwired/stimulus"

// "Voir QRcode" pop-up. On open it takes the exact width and height of
// the BonID wallet card (matchSelector) and sits right over it, so the two
// look like the same card. Bootstrap centres modals in the whole window,
// but the card is centred beside the 260px sidebar on desktop, so we line
// the pop-up up with the card instead. Falls back to the CSS size and
// Bootstrap centring when the card isn't on the page.
export default class extends Controller {
  static targets = ["card"]
  static values = { matchSelector: String }

  connect() {
    if (this.bound) return
    this.bound = true

    this.onShow = () => {
      this.clearOldMessages()
      this.pauseFlag()
      this.matchWalletCard()
    }

    // Re-measure once open: Bootstrap hides the page scrollbar on show,
    // which can nudge the card a few pixels.
    this.onShown = () => this.matchWalletCard()

    this.onHidden = () => {
      this.resumeFlagWithDelay()
    }

    this.onResize = () => {
      if (this.element.classList.contains("show")) this.matchWalletCard()
    }

    this.element.addEventListener("show.bs.modal", this.onShow)
    this.element.addEventListener("shown.bs.modal", this.onShown)
    this.element.addEventListener("hidden.bs.modal", this.onHidden)
    window.addEventListener("resize", this.onResize)
  }

  disconnect() {
    this.element.removeEventListener("show.bs.modal", this.onShow)
    this.element.removeEventListener("shown.bs.modal", this.onShown)
    this.element.removeEventListener("hidden.bs.modal", this.onHidden)
    window.removeEventListener("resize", this.onResize)
    this.bound = false
  }

  matchWalletCard() {
    if (!this.hasCardTarget || !this.matchSelectorValue) return
    const source = document.querySelector(this.matchSelectorValue)
    const dialog = this.element.querySelector(".modal-dialog")
    if (!source || !dialog) return

    const { left, width, height } = source.getBoundingClientRect()
    if (!width || !height) return

    dialog.style.maxWidth = `${Math.round(width)}px`
    dialog.style.marginLeft = `${Math.max(0, Math.round(left))}px`
    dialog.style.marginRight = "auto"
    this.cardTarget.style.minHeight = `${Math.round(height)}px`
  }

  clearOldMessages() {
    const notice = this.element.querySelector("[id$='qr_notice']")
    if (notice) notice.innerHTML = ""
  }

  pauseFlag() {
    document.querySelectorAll(".flag-overlay").forEach(el =>
      el.classList.remove("pulse-flag")
    )
  }

  resumeFlagWithDelay() {
    setTimeout(() => {
      document.querySelectorAll(".flag-overlay").forEach(el =>
        el.classList.add("pulse-flag")
      )
    }, 200)
  }
}
