import { Controller } from "@hotwired/stimulus"

// Auto-dismiss flash toasts. data-controller="flash" on each .bonid-toast.
// - delay: ms before closing (5s for success/info, 8s for errors)
// - hovering or focusing the toast pauses the countdown, so people can
//   finish reading; the thin timer bar shows the time left.
export default class extends Controller {
  static targets = ["timer"]
  static values = { delay: { type: Number, default: 5000 } }

  connect() {
    this.remaining = this.delayValue
    this.start()
  }

  disconnect() {
    this.clear()
  }

  start() {
    this.startedAt = Date.now()
    this.timeout = setTimeout(() => this.dismiss(), this.remaining)
    if (this.hasTimerTarget) {
      // Restart the bar's shrink animation from where it stopped.
      this.timerTarget.style.animationDuration = `${this.delayValue}ms`
      this.timerTarget.style.animationPlayState = "running"
    }
  }

  pause() {
    if (!this.timeout) return
    this.clear()
    this.remaining -= Date.now() - this.startedAt
    if (this.hasTimerTarget) this.timerTarget.style.animationPlayState = "paused"
  }

  resume() {
    if (this.timeout || this.closing) return
    this.start()
  }

  clear() {
    if (this.timeout) clearTimeout(this.timeout)
    this.timeout = null
  }

  dismiss() {
    if (this.closing) return
    this.closing = true
    this.clear()
    this.element.classList.add("fade-out")

    setTimeout(() => {
      const stack = this.element.closest(".bonid-toast-stack")
      this.element.remove()

      // Clean up the stack wrapper if no more toasts remain
      if (stack && stack.children.length === 0) stack.remove()
    }, 300)
  }
}
