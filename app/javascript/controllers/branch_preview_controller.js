import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="branch-preview"
export default class extends Controller {
  static targets = ["select", "output"]

  update() {
    const selected = this.selectTarget.selectedOptions[0]
    if (!selected || !selected.value) {
      this.outputTarget.textContent = "📍 Select a branch to preview its address."
      return
    }

    // Get preloaded data from option tag
    const address = selected.dataset.address
    this.outputTarget.innerHTML = `📍 <strong>${selected.text}</strong><br><small>${address || "Address unavailable"}</small>`
  }
}
