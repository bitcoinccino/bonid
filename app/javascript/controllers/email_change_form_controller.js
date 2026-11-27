import { Controller } from "@hotwired/stimulus"

// Change-email modal, step 1 (citizens/settings/edit).
//  - focuses the field when the modal opens (autofocus is ignored inside
//    Bootstrap modals, which are hidden at page load)
//  - keeps "Send code" disabled until the field holds a valid email
//  - flags the citizen's current address inline before they submit
//    (the server repeats this check, so it's a convenience, not a guard)
export default class extends Controller {
  static targets = ["input", "submit", "error"]
  static values = { current: String, sameEmailText: String }

  connect() {
    this.serverError = this.errorTarget.textContent.trim()
    this.modal = this.element.closest(".modal")
    this.onShown = () => this.inputTarget.focus()
    this.modal?.addEventListener("shown.bs.modal", this.onShown)
    this.validate({ initial: true })
  }

  disconnect() {
    this.modal?.removeEventListener("shown.bs.modal", this.onShown)
  }

  validate({ initial = false } = {}) {
    const value = this.inputTarget.value.trim().toLowerCase()
    const same = value !== "" && value === this.currentValue.toLowerCase()
    const valid = value !== "" && this.inputTarget.checkValidity()

    // Keep a server-sent error (e.g. "already used by another account")
    // visible until the citizen edits the field.
    let message = same ? this.sameEmailTextValue : ""
    if (initial && this.serverError) message = this.serverError

    this.errorTarget.textContent = message
    this.errorTarget.hidden = message === ""
    this.inputTarget.classList.toggle("is-invalid", message !== "")
    this.inputTarget.setAttribute("aria-invalid", message !== "" ? "true" : "false")
    this.submitTarget.disabled = !valid || same || (initial && !!this.serverError)
  }
}
