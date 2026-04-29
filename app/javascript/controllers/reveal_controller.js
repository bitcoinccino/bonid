import { Controller } from "@hotwired/stimulus"

// Swaps a masked-display element for an editor element on demand.
// Pattern:
//   <div data-controller="reveal">
//     <div data-reveal-target="display">…masked…<button data-action="click->reveal#show">Edit</button></div>
//     <div class="d-none" data-reveal-target="hidden">…editor…</div>
//   </div>
export default class extends Controller {
  static targets = ["display", "hidden"]

  show(event) {
    event.preventDefault()
    if (this.hasDisplayTarget) this.displayTarget.classList.add("d-none")
    if (this.hasHiddenTarget) {
      this.hiddenTarget.classList.remove("d-none")
      const input = this.hiddenTarget.querySelector("input, textarea, select")
      if (input) input.focus()
    }
  }
}
