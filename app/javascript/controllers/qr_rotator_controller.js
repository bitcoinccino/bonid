import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    interval: { type: Number, default: 60000 },
    expired: Boolean,
    expiresAt: Number
  }

  static targets = ["refreshForm"]

  connect() {
    this.onShown = () => this.modalOpened()
    this.onHidden = () => this.stop()
    document.addEventListener("turbo:render", () => this.stop())

    this.element.addEventListener("shown.bs.modal", this.onShown)
    this.element.addEventListener("hidden.bs.modal", this.onHidden)
  }

  modalOpened() {
    if (!this.hasRefreshFormTarget) return

    // Remove old notices
    const notice = document.querySelector(`[id$="qr_notice"]`)
    if (notice) notice.innerHTML = ""

    // Silent refresh once on modal open
    this.silentRefresh()

    // Start auto-rotation
    this.start()
  }

  silentRefresh() {
    // No popup
    this.refreshFormTarget.removeAttribute("data-turbo-confirm")

    // Append ?auto=true to the request
    const url = new URL(this.refreshFormTarget.action)
    url.searchParams.set("auto", "true")
    this.refreshFormTarget.action = url.toString()

    this.refreshFormTarget.requestSubmit()
  }

  start() {
    if (this.timer) return

    this.timer = setInterval(() => {
      this.silentRefresh()
    }, this.intervalValue)
  }

  stop() {
    if (!this.timer) return
    clearInterval(this.timer)
    this.timer = null
  }
}
