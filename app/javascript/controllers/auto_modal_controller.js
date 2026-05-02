import { Controller } from "@hotwired/stimulus"

// Auto-opens a Bootstrap modal on connect. Use it for "land back in the
// modal after a server round-trip" flows (e.g., the email-change verify
// step where the controller redirects to settings#edit and the citizen
// should land directly in code-entry).
//
// Markup:
//   <div data-controller="auto-modal" data-auto-modal-target-id-value="emailChangeModal"></div>
//
// Two reasons this exists instead of an inline <script> tag:
//   1. window.bootstrap may not be defined yet when an inline body script
//      runs (the application.js bundle is deferred / module-loaded after
//      parsing). The inline script no-ops silently and the modal renders
//      as plain block content sans backdrop.
//   2. Bootstrap modals inside positioned/transformed ancestors can lose
//      their fixed positioning. Appending to <body> first is the canonical
//      fix.
export default class extends Controller {
  static values = { targetId: String }

  connect() {
    this._tryOpen()
  }

  _tryOpen(attempt = 0) {
    const el = document.getElementById(this.targetIdValue)
    if (!el) return

    if (!window.bootstrap || !window.bootstrap.Modal) {
      // Bootstrap bundle hasn't loaded yet — wait one frame, retry up to ~2s.
      if (attempt < 60) {
        setTimeout(() => this._tryOpen(attempt + 1), 33)
      } else {
        console.warn("[auto-modal] window.bootstrap never loaded, giving up.")
      }
      return
    }

    // Move the modal to <body> so its fixed positioning + backdrop aren't
    // clipped by ancestor margin/padding/transform on the layout shell.
    if (el.parentNode !== document.body) {
      document.body.appendChild(el)
    }

    window.bootstrap.Modal.getOrCreateInstance(el).show()
  }
}
