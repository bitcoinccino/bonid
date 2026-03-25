import { Controller } from "@hotwired/stimulus"

// Controller to handle unit -> specialty cascading dropdown for officers
export default class extends Controller {
  static targets = ["unitSelect", "specialtySelect"]

  connect() {
    // Load unit options from JSON script tag
    const jsonElement = document.getElementById("unit-options-json")
    this.unitOptions = jsonElement ? JSON.parse(jsonElement.textContent) : {}
  }

  updateSpecialties() {
    const selectedUnit = this.unitSelectTarget.value
    const specialties = this.unitOptions[selectedUnit] || []

    // Use the target directly since both selects are within the controller scope
    if (!this.hasSpecialtySelectTarget) return

    const specialtySelect = this.specialtySelectTarget

    // Clear and repopulate specialty options
    specialtySelect.innerHTML = '<option value="">Select Specialty</option>'

    specialties.forEach((specialty) => {
      const opt = document.createElement("option")
      opt.value = specialty
      opt.textContent = specialty
      specialtySelect.appendChild(opt)
    })
  }
}
