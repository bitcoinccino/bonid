// app/javascript/controllers/map_controller.js
import { Controller } from "@hotwired/stimulus"
import L from "leaflet"

export default class extends Controller {
  static values = { latitude: Number, longitude: Number, zoom: Number }

  connect() {
    if (!this.latitudeValue || !this.longitudeValue) return

    const map = L.map(this.element).setView([this.latitudeValue, this.longitudeValue], this.zoomValue || 13)

    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: '&copy; OpenStreetMap contributors'
    }).addTo(map)

    L.marker([this.latitudeValue, this.longitudeValue]).addTo(map)
  }
}


