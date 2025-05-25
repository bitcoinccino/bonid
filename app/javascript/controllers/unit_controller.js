// app/javascript/controllers/unit_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["name", "type"];
  static values = { options: Object };

  connect() {
    this.updateTypes(); // Initialize unit_type options based on current unit_name
  }

  updateTypes() {
    const unitName = this.nameTarget.value;
    const unitTypeSelect = this.typeTarget;
    const options = this.optionsValue[unitName] || [];

    // Clear existing options except the prompt
    unitTypeSelect.innerHTML = '<option value="">Select Unit Type</option>';

    // Populate new options
    options.forEach(type => {
      const option = document.createElement("option");
      option.value = type;
      option.text = type;
      unitTypeSelect.appendChild(option);
    });

    // Restore saved unit_type if valid
    const currentUnitType = unitTypeSelect.dataset.currentValue || this.element.querySelector('[name="officer[unit_type]"]').value;
    if (options.includes(currentUnitType)) {
      unitTypeSelect.value = currentUnitType;
    }
  }
}