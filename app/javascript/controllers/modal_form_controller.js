import { Controller } from "@hotwired/stimulus"

// Gates a modal form's primary button (see shared/_modal_footer):
// enabled only once the form has changed AND passes the browser's own
// validation (required fields, email/number formats, …).
//
//  - Optional forms (physical, health, social): Save stays disabled until
//    something is edited, so an untouched Save never fires a no-op request.
//  - Forms with required fields (family, emergency contacts): Save also
//    waits for those fields to be valid.
//
// Rows added or removed by other controllers (nested-form, emergency-
// contacts) change the form's data, so a MutationObserver re-checks then.
//
// Row-level required fields: inside a [data-modal-form-group] (one family
// member, one emergency contact), fields marked [data-modal-form-required]
// become required only once that row has been edited. Untouched optional
// rows never block Save, and a half-filled row can't be saved without the
// fields the server needs (it would otherwise drop the row silently).
//
// Auth pages (login, sign-up, verify code) set require-change to false:
// a pre-filled email after an error must stay resubmittable as-is.
export default class extends Controller {
  static targets = ["submit"]
  static values = { requireChange: { type: Boolean, default: true } }

  connect() {
    this.form = this.element.tagName === "FORM" ? this.element : this.element.querySelector("form")
    if (!this.form) return

    this.groupInitial = new WeakMap()
    this.initial = this.snapshot()
    this.check = this.check.bind(this)
    this.form.addEventListener("input", this.check)
    this.form.addEventListener("change", this.check)
    this.observer = new MutationObserver(() => this.check())
    this.observer.observe(this.form, { childList: true, subtree: true })
    this.check()
  }

  disconnect() {
    this.form?.removeEventListener("input", this.check)
    this.form?.removeEventListener("change", this.check)
    this.observer?.disconnect()
  }

  check() {
    if (!this.hasSubmitTarget) return
    this.applyRowRequirements()
    const dirty = !this.requireChangeValue || this.snapshot() !== this.initial
    const valid = this.form.checkValidity()
    this.submitTargets.forEach((btn) => { btn.disabled = !(dirty && valid) })
  }

  applyRowRequirements() {
    this.form.querySelectorAll("[data-modal-form-group]").forEach((group) => {
      const state = this.groupState(group)
      // First time we see a row (page load, or just added) is its baseline.
      if (!this.groupInitial.has(group)) this.groupInitial.set(group, state)
      const destroyed = group.querySelector("input[name$='[_destroy]']")?.value
      const removed = destroyed === "1" || destroyed === "true" || group.offsetParent === null && group.style.display === "none"
      const edited = state !== this.groupInitial.get(group)
      group.querySelectorAll("[data-modal-form-required]").forEach((el) => {
        el.required = edited && !removed
      })
    })
  }

  groupState(group) {
    return [...group.querySelectorAll("input, select, textarea")]
      .filter((el) => el.name && !["hidden", "submit", "button"].includes(el.type))
      .map((el) => (el.type === "radio" || el.type === "checkbox") ? `${el.name}:${el.value}:${el.checked}` : `${el.name}=${el.value}`)
      .join("&")
  }

  // Comparable string of everything the form would send (minus the CSRF
  // token, which never changes on its own).
  snapshot() {
    const parts = []
    for (const [name, value] of new FormData(this.form)) {
      if (name === "authenticity_token") continue
      parts.push(`${name}=${value instanceof File ? `${value.name}:${value.size}` : value}`)
    }
    return parts.join("&")
  }
}
