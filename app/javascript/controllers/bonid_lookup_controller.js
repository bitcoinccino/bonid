import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "result", "toast"]

  connect() {
    // Optional: automatically fetch if input already has value
    if (this.hasInputTarget && this.inputTarget.value.trim()) this.fetch()
  }

  async fetch(event) {
    event?.preventDefault()

    const bonid = this.inputTarget.value.trim()
    if (!bonid) return

    this.setResult("⏳ Looking up BonID...")

    try {
      const response = await fetch(`/bonid_lookup/${bonid}`, {
        headers: { "Accept": "application/json" },
      })
      if (!response.ok) throw new Error("Network response was not OK")

      const data = await response.json()

      if (data.found) {
        this.setResult(`✅ Match: ${data.name}`, "text-success")
        this.showToast("BonID verified successfully!")

        // Close modal smoothly after a short delay (e.g., 1.5s)
        setTimeout(() => {
          this.closeModal()
        }, 1500)
      } else {
        this.setResult("❌ BonID not found", "text-danger")
      }
    } catch (error) {
      console.error("BonID lookup failed:", error)
      this.setResult("⚠️ Lookup error", "text-danger")
    }
  }

  setResult(message, cls = "") {
    if (this.hasResultTarget) {
      this.resultTarget.innerHTML = `<div class="${cls}">${message}</div>`
    }
  }

  showToast(message) {
    if (!this.hasToastTarget) return

    this.toastTarget.textContent = message
    this.toastTarget.classList.remove("d-none")

    setTimeout(() => {
      this.toastTarget.classList.add("d-none")
    }, 3000)
  }

  closeModal() {
    // Bootstrap 5 way to close modal programmatically
    const modalEl = this.element.closest(".modal")
    if (!modalEl) return

    const modal = bootstrap.Modal.getInstance(modalEl)
    if (modal) modal.hide()
  }
}
