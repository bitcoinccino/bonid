import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="partner-form"
export default class extends Controller {
  static targets = ["email", "useCases", "sector", "website", "humanToken"]

  connect() {
    this.startTime = Date.now()

    // Set human token after 3s
    setTimeout(() => {
      if (this.hasHumanTokenTarget) {
        this.humanTokenTarget.value = "human_" + Math.random().toString(36).slice(2, 9)
      }
    }, 3000)
  }

  validate(event) {
    // Honeypot check
    if (this.websiteTarget?.value) {
      event.preventDefault()
      console.warn("Bot detected: honeypot filled")
      return
    }

    // Too fast submission check
    if (Date.now() - this.startTime < 2000) {
      event.preventDefault()
      alert("Form submitted too quickly. Please try again.")
      return
    }

    // Human token check
    if (this.hasHumanTokenTarget && !this.humanTokenTarget.value.startsWith("human_")) {
      event.preventDefault()
      alert("Please wait a moment before submitting.")
      return
    }

    // Email validation
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    if (!emailRegex.test(this.emailTarget.value)) {
      event.preventDefault()
      alert("Please enter a valid email address.")
      return
    }

    // Use cases required
    if (this.useCasesTarget && this.useCasesTarget.selectedOptions.length === 0) {
      event.preventDefault()
      alert("Please select at least one use case.")
      return
    }

    // Sector required
    if (this.sectorTarget && !this.sectorTarget.value) {
      event.preventDefault()
      alert("Please select a department sector.")
    }
  }
}
