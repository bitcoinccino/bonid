import { Controller } from "@hotwired/stimulus"

// Topbar notification bell: opening the dropdown marks notifications as
// seen. The red badges disappear right away; items stay highlighted
// ("Nouveau") for this view so the citizen still sees what was new.
export default class extends Controller {
  static targets = ["badge"]
  static values = { url: String }

  connect() {
    this.onShown = this.markSeen.bind(this)
    this.element.addEventListener("shown.bs.dropdown", this.onShown)
  }

  disconnect() {
    this.element.removeEventListener("shown.bs.dropdown", this.onShown)
  }

  markSeen() {
    if (this.sent || !this.hasBadgeTarget) return
    this.sent = true

    this.badgeTargets.forEach(el => el.remove())

    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(this.urlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": token, "Accept": "application/json" },
      credentials: "same-origin",
      keepalive: true
    }).catch(() => { this.sent = false })
  }
}
