import { Controller } from "@hotwired/stimulus";
import L from "leaflet";
import "leaflet/dist/leaflet.css";

// Connects to data-controller="map"
export default class extends Controller {
  static values = {
    latitude: Number,
    longitude: Number,
    label: String
  }

  connect() {
    if (!this.hasLatitudeValue || !this.hasLongitudeValue) {
      console.warn("Map: Missing coordinates");
      return;
    }

    const map = L.map(this.element).setView(
      [this.latitudeValue, this.longitudeValue],
      16
    );

    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: "&copy; OpenStreetMap contributors"
    }).addTo(map);

    L.marker([this.latitudeValue, this.longitudeValue]).addTo(map)
      .bindPopup(this.labelValue || "Location")
      .openPopup();
  }
}
