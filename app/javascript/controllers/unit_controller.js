import { Controller } from "@hotwired/stimulus"

// Stimulus controller to handle sector logic and animated display of Law Enforcement fields.
export default class extends Controller {
  static targets = ["wrapper", "type", "name"]

  connect() {
    const jsonElement = document.getElementById("unit-options-json")
    this.unitOptions = jsonElement ? JSON.parse(jsonElement.textContent) : {}

    // Prepare animation classes
    this.wrapperTarget.classList.add("transition-collapse")

    // If prefilled sector is law_enforcement, show immediately
    const sectorSelect = this.element.querySelector("select[name*='sector']")
    if (sectorSelect && this.isLawEnforcement(sectorSelect.value)) {
      this.showUnitFields(true) // true = instant show (no animation)
      this.populateUnitTypes()
    }
  }

  toggleUnitFields(event) {
    const selected = event.target.value
    if (this.isLawEnforcement(selected)) {
      this.showUnitFields()
      this.populateUnitTypes()
    } else {
      this.hideUnitFields()
    }
  }

  updateUnitNames() {
    const selectedType = this.typeTarget.value
    const names = this.unitOptions[selectedType] || []

    this.nameTarget.innerHTML = '<option value="">Select Unit Name</option>'
    names.forEach((name) => {
      const opt = document.createElement("option")
      opt.value = name
      opt.textContent = name
      this.nameTarget.appendChild(opt)
    })
  }

  // --- Internal Helpers ---
  isLawEnforcement(value) {
    if (!value) return false
    return value.toLowerCase().includes("law_enforcement") || value.toLowerCase().includes("law enforcement")
  }

  showUnitFields(instant = false) {
    const el = this.wrapperTarget
    el.classList.remove("d-none")

    if (instant) {
      el.classList.add("showing")
      return
    }

    el.style.height = "0px"
    el.classList.add("showing")

    requestAnimationFrame(() => {
      el.style.height = el.scrollHeight + "px"
      el.classList.add("fade-in")
    })

    // reset height after animation
    setTimeout(() => {
      el.style.height = ""
      el.classList.remove("fade-in")
    }, 300)
  }

  hideUnitFields() {
    const el = this.wrapperTarget
    el.style.height = el.scrollHeight + "px"
    requestAnimationFrame(() => {
      el.style.height = "0px"
      el.classList.add("fade-out")
    })

    setTimeout(() => {
      el.classList.add("d-none")
      el.classList.remove("fade-out", "showing")
      el.style.height = ""
    }, 300)
  }

  populateUnitTypes() {
    if (!this.typeTarget || !this.unitOptions) return
    this.typeTarget.innerHTML = '<option value="">Select Unit Type</option>'
    Object.keys(this.unitOptions).forEach((type) => {
      const opt = document.createElement("option")
      opt.value = type
      opt.textContent = type
      this.typeTarget.appendChild(opt)
    })
  }
}

