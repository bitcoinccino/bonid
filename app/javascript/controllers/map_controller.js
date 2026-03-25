// app/javascript/controllers/map_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["element"];
  static values = {
    latitude: Number,
    longitude: Number,
    label: String,
    severity: String
  };

  connect() {
    const L = window.L;
    if (!L || !this.hasElementTarget) {
      console.error("Leaflet is not loaded or map container is missing.");
      return;
    }

    const lat = this.validCoordinate(this.latitudeValue, 18.5392);
    const lng = this.validCoordinate(this.longitudeValue, -72.3350);
    const severityClass = `severity-${this.severityValue?.toLowerCase() || "unknown"}`;

    try {
      // Initialize map
      this.map = L.map(this.elementTarget).setView([lat, lng], 13);

      // Add OpenStreetMap tile layer
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        attribution: '© <a href="https://www.openstreetmap.org/">OpenStreetMap</a> contributors',
        maxZoom: 18,
      }).addTo(this.map);

      // Create marker HTML
      const markerHtml = `
        <div class="custom-marker ${severityClass}">
          <i class="ri-police-car-fill"></i>
        </div>
      `;

      // Add custom marker
      L.marker([lat, lng], {
        icon: L.divIcon({
          className: "",
          html: markerHtml,
          iconSize: [36, 36],
          iconAnchor: [18, 36],
          popupAnchor: [0, -36],
        }),
      })
        .addTo(this.map)
        .bindPopup(this.labelValue || "Incident Location")
        .openPopup();

      // Resize handler
      this.invalidate = () => this.map.invalidateSize();
      setTimeout(this.invalidate, 500);
      this.elementTarget.addEventListener("turbo:frame-load", this.invalidate);
      window.addEventListener("resize", this.invalidate);
      document.addEventListener("shown.bs.modal", this.invalidate);
    } catch (error) {
      console.error("Map failed to load:", error);
      this.elementTarget.innerHTML = "<p class='text-danger'>Map error occurred.</p>";
    }
  }

  validCoordinate(value, fallback) {
    return isNaN(value) || value === 0 ? fallback : value;
  }

  disconnect() {
    if (this.map) {
      this.map.remove();
      this.map = null;
    }
    this.elementTarget.removeEventListener("turbo:frame-load", this.invalidate);
    window.removeEventListener("resize", this.invalidate);
    document.removeEventListener("shown.bs.modal", this.invalidate);
  }
}
