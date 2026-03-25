// app/javascript/controllers/qr_modal_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    if (this.bound) return
    this.bound = true

    this.onShow = () => {
      this.clearOldMessages()
      this.pauseFlag()
    }

    this.onHidden = () => {
      this.resumeFlagWithDelay()
    }

    this.element.addEventListener("show.bs.modal", this.onShow)
    this.element.addEventListener("hidden.bs.modal", this.onHidden)
  }

  disconnect() {
    this.element.removeEventListener("show.bs.modal", this.onShow)
    this.element.removeEventListener("hidden.bs.modal", this.onHidden)
    this.bound = false
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
