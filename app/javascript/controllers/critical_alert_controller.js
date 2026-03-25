// app/javascript/controllers/critical_alert_controller.js
// Emergency broadcast toggle for Partner Portal Law Enforcement dashboard
// Activates/deactivates "Critical Incident" mode with confirmation modal

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { toggleUrl: String }

  // Opens the Bootstrap confirmation modal
  requestToggle(event) {
    event.preventDefault()
    const modal = document.getElementById("criticalAlertModal")
    if (modal) {
      const bsModal = bootstrap.Modal.getOrCreateInstance(modal)
      bsModal.show()
    }
  }

  // Called when user confirms toggle in the modal
  async confirmToggle(event) {
    event.preventDefault()

    const messageInput = document.getElementById("criticalAlertMessage")
    const message = messageInput ? messageInput.value.trim() : ""
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const response = await fetch(this.toggleUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": csrfToken || "",
          "Accept": "text/html"
        },
        body: `message=${encodeURIComponent(message)}`
      })

      // Close modal
      const modal = document.getElementById("criticalAlertModal")
      if (modal) {
        const bsModal = bootstrap.Modal.getInstance(modal)
        bsModal?.hide()
      }

      // Follow redirect (Turbo Drive will handle the redirect response)
      if (response.redirected) {
        window.Turbo.visit(response.url)
      } else {
        // Reload to show updated state
        window.Turbo.visit(window.location.href)
      }
    } catch (err) {
      console.error("[CriticalAlert] Toggle failed:", err)
      // Fallback: reload page
      window.location.reload()
    }
  }
}
