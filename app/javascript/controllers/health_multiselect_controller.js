import { Controller } from "@hotwired/stimulus"

// Handles multi-select dropdown behavior for health fields
// Renders inline chips inside the dropdown trigger button
//
// Copy can be localized from the page:
//   data-health-multiselect-placeholder-value="Pa konnen okenn"
//   data-health-multiselect-selected-value="%{count} chwazi"
// Chips show each option's visible label (not its stored value).
export default class extends Controller {
  static targets = ["button", "label", "chipArea"]
  static values = { placeholder: String, selected: String }

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
        html += `<span class="health-inline-chip">${this._escapeHtml(this._optionLabel(cb))}</span>`
      })
      chipArea.innerHTML = html
    }
  }

  getPlaceholder(field) {
    if (this.hasPlaceholderValue && this.placeholderValue) return this.placeholderValue
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
      this.labelTarget.textContent = this._optionLabel(checkboxes[0])
      this.labelTarget.classList.remove("text-muted")
    } else {
      this.labelTarget.textContent = (this.hasSelectedValue && this.selectedValue)
        ? this.selectedValue.replace("%{count}", count)
        : `${count} selected`
      this.labelTarget.classList.remove("text-muted")
    }
  }

  // Visible text of the checkbox's <label> (localized), else its value.
  _optionLabel(cb) {
    const span = cb.closest("label")?.querySelector("span")
    return span?.textContent?.trim() || cb.value
  }

  _escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
