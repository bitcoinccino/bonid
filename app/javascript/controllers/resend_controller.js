import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "countdown"]
  static values = { cooldown: Number }

  connect() {
    this.reset()
  }

  startCooldown(event) {
    event.preventDefault()

    // Let the form actually submit (Turbo handles the request),
    // but also trigger the cooldown immediately
    this.disableButton()
    this.startTimer()
  }

  disableButton() {
    if (this.hasButtonTarget) {
      this.buttonTarget.disabled = true
      this.buttonTarget.textContent = "Resent!"
    }
  }

  startTimer() {
    let seconds = this.cooldownValue
    this.updateCountdown(seconds)

    this.timer = setInterval(() => {
      seconds--
      this.updateCountdown(seconds)
      if (seconds <= 0) {
        this.reset()
      }
    }, 1000)
  }

  updateCountdown(seconds) {
    if (this.hasCountdownTarget) {
      this.countdownTarget.textContent =
        seconds > 0 ? `(${seconds}s)` : ""
    }
  }

  reset() {
    if (this.timer) clearInterval(this.timer)
    if (this.hasButtonTarget) {
      this.buttonTarget.disabled = false
      this.buttonTarget.textContent = "Resend Code"
    }
    if (this.hasCountdownTarget) {
      this.countdownTarget.textContent = ""
    }
  }
}
