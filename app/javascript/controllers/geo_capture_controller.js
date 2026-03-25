import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["latitude", "longitude", "status"]

  connect() {
    if (navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(
        (pos) => {
          const { latitude, longitude } = pos.coords
          this.latitudeTarget.value = latitude
          this.longitudeTarget.value = longitude
          if (this.hasStatusTarget) this.statusTarget.textContent = "📍 Location detected"
        },
        (err) => {
          console.warn("Geolocation not available:", err.message)
          if (this.hasStatusTarget) this.statusTarget.textContent = "⚠️ Location unavailable"
        }
      )
    } else {
      console.warn("Browser does not support geolocation.")
      if (this.hasStatusTarget) this.statusTarget.textContent = "❌ No geolocation support"
    }
  }
}
