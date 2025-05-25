// app/javascript/controllers/bonid_lookup_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "result", "name", "userId", "editBtn", "toast"]

  async fetch() {
    const bonid = this.inputTarget.value.trim()
    if (!bonid) return

    try {
      const response = await fetch(`/bonid_lookup/${bonid}`)
      const data = await response.json()

      if (data.found) {
        this.inputTarget.readOnly = true
        this.resultTarget.innerHTML = `
          <div class="text-success">✅ Match: ${data.name}</div>
        `
        this.editBtnTarget.classList.remove("d-none")

        this.nameTarget.value = data.name
        this.userIdTarget.value = data.user_id
      } else {
        this.resultTarget.innerHTML = `<div class="text-danger">❌ BonID not found</div>`
      }
    } catch (error) {
      console.error("BonID lookup failed", error)
      this.resultTarget.innerHTML = `<div class="text-danger">⚠️ Lookup error</div>`
    }
  }

  edit() {
    this.inputTarget.readOnly = false
    this.inputTarget.focus()
    this.inputTarget.value = ""
    this.nameTarget.value = ""
    this.userIdTarget.value = ""
    this.resultTarget.innerHTML = ""
    this.editBtnTarget.classList.add("d-none")

    this.showToast("You can now edit the BonID.")
  }

  showToast(message) {
    if (!this.hasToastTarget) return

    this.toastTarget.textContent = message
    this.toastTarget.classList.remove("d-none")

    setTimeout(() => {
      this.toastTarget.classList.add("d-none")
    }, 3000)
  }
}

