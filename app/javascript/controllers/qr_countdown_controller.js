import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    interval: { type: Number, default: 60 } // seconds until next refresh
  }
  static targets = ["display"]

  connect() {
    // Listen for modal show to start countdown
    this.modal = this.element.closest('.modal')
    if (this.modal) {
      this.modal.addEventListener('shown.bs.modal', () => this.startCountdown())
      this.modal.addEventListener('hidden.bs.modal', () => this.stopCountdown())
    }

    // Listen for turbo stream updates (QR refresh) to reset countdown
    document.addEventListener('turbo:before-stream-render', (e) => {
      if (e.target.querySelector && e.target.querySelector('[id$="qr_wrapper"]')) {
        this.resetCountdown()
      }
    })
  }

  disconnect() {
    this.stopCountdown()
  }

  startCountdown() {
    this.remaining = this.intervalValue
    this.updateDisplay()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  stopCountdown() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  resetCountdown() {
    this.remaining = this.intervalValue
    this.updateDisplay()
  }

  tick() {
    this.remaining -= 1

    if (this.remaining <= 0) {
      this.remaining = this.intervalValue // Reset for next cycle
    }

    this.updateDisplay()
  }

  updateDisplay() {
    const displayEl = this.hasDisplayTarget ? this.displayTarget : this.element
    const minutes = Math.floor(this.remaining / 60)
    const seconds = this.remaining % 60
    const paddedSeconds = seconds.toString().padStart(2, '0')
    displayEl.textContent = `${minutes}:${paddedSeconds}`
  }
}
