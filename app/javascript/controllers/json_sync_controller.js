
import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="json-sync"
export default class extends Controller {
  static targets = ["form", "preview"]

  update() {
    if (!this.hasFormTarget) return // ✅ guard
    const formEl = this.formTarget

    // ✅ Ensure it’s actually an HTMLFormElement
    if (!(formEl instanceof HTMLFormElement)) {
      console.warn("json-sync: formTarget is not a valid HTMLFormElement")
      return
    }

    try {
      const formData = new FormData(formEl)
      const data = {}

      for (const [key, value] of formData.entries()) {
        if (key.startsWith("verification_record[data_")) {
          const cleanKey = key.replace("verification_record[data_", "").replace("]", "")
          data[cleanKey] = this._normalize(value)
        }
      }

      if (this.hasPreviewTarget) {
        this.previewTarget.hidden = true
        this.previewTarget.textContent = JSON.stringify(data, null, 2)
      }
    } catch (err) {
      console.error("json-sync update error:", err)
      if (this.hasPreviewTarget) {
        this.previewTarget.hidden = false
        this.previewTarget.textContent = `⚠️ ${err.message}`
      }
    }
  }

  _normalize(value) {
    if (value === "true") return true
    if (value === "false") return false
    if (value === "") return null
    if (!isNaN(value) && value.trim() !== "") return Number(value)
    return value
  }
}
