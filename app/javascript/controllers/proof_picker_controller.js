import { Controller } from "@hotwired/stimulus"

// Address-proof picker. Replaces the native <select> with a Bootstrap
// modal that lists each option as a tappable card with an icon. Cleaner
// on mobile (large finger targets) and surfaces what the document type
// is "for" via the icon vocabulary (drop = water bill, bank = statement,
// exchange-funds = remittance receipt, etc.).
//
// Markup pattern:
//   <div data-controller="proof-picker">
//     <input type="hidden" data-proof-picker-target="hidden" name="...">
//     <button data-bs-toggle="modal" data-bs-target="#proofPickerModal">
//       <i data-proof-picker-target="icon"></i>
//       <span data-proof-picker-target="display">Chwazi…</span>
//     </button>
//     <div class="modal" id="proofPickerModal">
//       <button data-action="click->proof-picker#pick"
//               data-value="..." data-label="..." data-icon="ri-...">…</button>
//     </div>
//   </div>
export default class extends Controller {
  static targets = ["hidden", "display", "icon"]

  pick(event) {
    const card  = event.currentTarget
    const value = card.dataset.value
    const label = card.dataset.label
    const icon  = card.dataset.icon

    if (this.hasHiddenTarget) {
      this.hiddenTarget.value = value
      this.hiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
    }

    if (this.hasDisplayTarget) {
      this.displayTarget.textContent = label
      this.displayTarget.classList.remove("text-muted")
      this.displayTarget.classList.add("text-dark", "fw-semibold")
    }

    if (this.hasIconTarget) {
      this.iconTarget.className = `${icon} me-2`
      this.iconTarget.style.color = "var(--primary)"
    }

    const modalEl = this.element.querySelector(".modal.show")
    const Modal   = window.bootstrap && window.bootstrap.Modal
    if (modalEl && Modal) Modal.getOrCreateInstance(modalEl).hide()
  }
}
