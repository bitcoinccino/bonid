import { Controller } from "@hotwired/stimulus"

// Handles multi-select dropdown behavior for health fields
// Renders inline chips inside the dropdown trigger button
export default class extends Controller {
  static targets = ["button", "label", "chipArea"]

  connect() {
    this.updateLabel()
  }

  updateLabel() {
    const checkboxes = this.element.querySelectorAll("input[type='checkbox']:checked")
    const count = checkboxes.length
    const field = this.element.dataset.field

    if (!this.hasChipAreaTarget) {
      // Fallback: just update text label
      this._updateTextLabel(checkboxes, count, field)
      return
    }

    const chipArea = this.chipAreaTarget

    if (count === 0) {
      chipArea.innerHTML = `<span data-health-multiselect-target="label" class="text-muted">${this.getPlaceholder(field)}</span>`
    } else {
      // Build inline chips
      let html = ""
      checkboxes.forEach((cb) => {
        html += `<span class="health-inline-chip">${this._escapeHtml(cb.value)}</span>`
      })
      chipArea.innerHTML = html
    }
  }

  getPlaceholder(field) {
    const placeholders = {
      allergies: "None known",
      chronic_conditions: "None known",
      medications: "None known"
    }
    return placeholders[field] || "Select options..."
  }

  _updateTextLabel(checkboxes, count, field) {
    if (!this.hasLabelTarget) return
    if (count === 0) {
      this.labelTarget.textContent = this.getPlaceholder(field)
      this.labelTarget.classList.add("text-muted")
    } else if (count === 1) {
      this.labelTarget.textContent = checkboxes[0].value
      this.labelTarget.classList.remove("text-muted")
    } else {
      this.labelTarget.textContent = `${count} selected`
      this.labelTarget.classList.remove("text-muted")
    }
  }

  _escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
