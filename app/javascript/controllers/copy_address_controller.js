import { Controller } from "@hotwired/stimulus"

// Copy a formatted postal address (rendered into a hidden-friendly <pre>)
// to the clipboard. Used by the diplomatic-missions index to give partner
// admins a one-click copy of the UPU S42-formatted block — handy for
// pasting into mailing labels, internal docs, or shipping integrations.
//
// Targets:
//   source — the element whose textContent gets copied
//   button — the trigger (we briefly swap its icon to confirm success)
export default class extends Controller {
  static targets = ["source", "button"]

  async copy() {
    const text = this.sourceTarget.innerText.trim()
    if (!text) return

    try {
      await navigator.clipboard.writeText(text)
      this.flashSuccess()
    } catch (err) {
      console.error("Clipboard write failed:", err)
      this.flashFailure()
    }
  }

  flashSuccess() {
    if (!this.hasButtonTarget) return
    const btn = this.buttonTarget
    const original = btn.innerHTML
    btn.innerHTML = '<i class="ri-check-line"></i>'
    btn.classList.remove("btn-outline-secondary")
    btn.classList.add("btn-success")
    setTimeout(() => {
      btn.innerHTML = original
      btn.classList.remove("btn-success")
      btn.classList.add("btn-outline-secondary")
    }, 1200)
  }

  flashFailure() {
    if (!this.hasButtonTarget) return
    const btn = this.buttonTarget
    btn.classList.add("btn-danger")
    setTimeout(() => btn.classList.remove("btn-danger"), 1200)
  }
}
