import { Controller } from "@hotwired/stimulus"

// Candidate registration wizard — BonID pre-fill.
// Hits the partner-portal lookup endpoint and fills identity / residence
// fields with data from the matched (verified) BonID user. Only fills
// fields that are currently blank so agent edits aren't clobbered.
export default class extends Controller {
  static targets = ["code", "hint"]
  static values  = { url: String }

  async fetch(event) {
    event?.preventDefault()

    const code = this.codeTarget.value.trim().toUpperCase()
    if (!code) {
      this.setHint("Antre yon nimewo BonID anvan.", "text-warning")
      return
    }

    this.setHint("⏳ Ap chache BonID a...", "text-muted")

    try {
      const url = `${this.urlValue}?bonid=${encodeURIComponent(code)}`
      const res = await fetch(url, { headers: { "Accept": "application/json" } })
      if (!res.ok) throw new Error("Network error")

      const data = await res.json()

      if (!data.found) {
        this.setHint("❌ Pa gen BonID verifye ki koresponn. Ranpli manyèl.", "text-danger")
        return
      }

      const filled = this.#applyFields(data.fields || {})
      this.setHint(
        `✅ Pre-ranpli ${filled} chan ak BonID verifye. Ou ka modifye yo avan soumèt.`,
        "text-success"
      )
    } catch (err) {
      console.error("BonID prefill failed:", err)
      this.setHint("⚠️ Erè pandan rekèt la. Eseye ankò.", "text-danger")
    }
  }

  #applyFields(fields) {
    let count = 0
    Object.entries(fields).forEach(([key, value]) => {
      if (value == null || value === "") return
      const el = this.element.querySelector(`[name="election_candidate[${key}]"]`)
      if (!el) return
      // Don't overwrite what the agent already typed.
      if (el.value && el.value.trim() !== "") return
      el.value = value
      el.classList.add("is-valid")
      count++
    })
    return count
  }

  setHint(message, cls = "") {
    if (!this.hasHintTarget) return
    this.hintTarget.className = `form-text ${cls}`
    this.hintTarget.textContent = message
  }
}
