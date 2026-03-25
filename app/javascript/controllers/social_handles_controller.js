import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["template", "handles"]

  add(event) {
    event.preventDefault()
    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, new Date().getTime())
    this.handlesTarget.insertAdjacentHTML("beforeend", content)
  }

  markForRemoval(event) {
    event.preventDefault()
    const wrapper = event.target.closest(".nested-fields")
    wrapper.querySelector("input[name*='_destroy']").value = "1" // mark for destruction
    wrapper.style.display = "none" // hide visually
  }

  remove(event) {
    event.preventDefault()
    const wrapper = event.target.closest(".nested-fields")
    if (!wrapper) return

    // New records can be removed from DOM, persisted records need soft delete
    if (wrapper.dataset.newRecord === "true") {
      wrapper.remove()
    } else {
      const destroyInput = wrapper.querySelector("input[name*='_destroy']")
      if (destroyInput) destroyInput.value = "1"
      wrapper.style.display = "none"
    }
  }
}
