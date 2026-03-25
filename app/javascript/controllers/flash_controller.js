import { Controller } from "@hotwired/stimulus"

// Auto-dismiss flash/toast messages after delay with smooth animation.
// data-controller="flash" on each .bonid-toast element.
export default class extends Controller {
  connect() {
    this.timeout = setTimeout(() => this.dismiss(), 5000)
  }

  disconnect() {
    if (this.timeout) clearTimeout(this.timeout)
  }

  dismiss() {
    if (this.timeout) clearTimeout(this.timeout)
    this.element.classList.add("fade-out")

    setTimeout(() => {
      const stack = this.element.closest('.bonid-toast-stack')
      this.element.remove()

      // Clean up the stack wrapper if no more toasts remain
      if (stack && stack.children.length === 0) {
        stack.remove()
      }
    }, 300)
  }
}
