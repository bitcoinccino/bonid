// app/javascript/controllers/nested_form_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["template", "wrapper", "container"]

  connect() {
    console.log("🔗 NestedFormController connected")
  }

  // Alias for backwards compatibility
  add(event) {
    this.addAssociation(event)
  }

  addAssociation(event) {
    event.preventDefault()
    const time = new Date().getTime() // unique key
    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, time)

    // Create a temporary container to parse the HTML
    const temp = document.createElement("div")
    temp.innerHTML = content

    // Support both "wrapper" and "container" target names
    const targetElement = this.hasWrapperTarget ? this.wrapperTarget : this.containerTarget

    // Append the actual DOM nodes (not innerHTML string) so Stimulus can observe
    while (temp.firstChild) {
      targetElement.appendChild(temp.firstChild)
    }
  }

  // Alias for backwards compatibility
  remove(event) {
    this.removeAssociation(event)
  }

  removeAssociation(event) {
    event.preventDefault()
    const wrapper = event.target.closest(".nested-fields")

    if (!wrapper) {
      console.warn("Could not find .nested-fields wrapper")
      return
    }

    // Check for destroy flag input (for persisted records)
    const destroyFlag = wrapper.querySelector("input[name*='_destroy']") ||
                        wrapper.querySelector("input.destroy-flag")

    if (destroyFlag) {
      destroyFlag.value = "1"
      wrapper.style.display = "none"
    } else {
      wrapper.remove()
    }
  }
}
