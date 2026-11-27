// Opens a Bootstrap dropdown elsewhere on the page, e.g. the sign-up page's
// "We'll email you in English · Change" link opens the globe language menu.
//   <button data-controller="open-dropdown"
//           data-open-dropdown-toggle-value=".auth-lang-toggle"
//           data-action="open-dropdown#open">
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { toggle: String }

  open(event) {
    event.preventDefault()
    // The click would otherwise reach Bootstrap's outside-click handler and
    // close the menu right after it opens.
    event.stopPropagation()
    const toggle = document.querySelector(this.toggleValue)
    if (!toggle || !window.bootstrap) return
    window.bootstrap.Dropdown.getOrCreateInstance(toggle).show()
    toggle.focus()
  }
}
