import { Controller } from "@hotwired/stimulus";
import L from "leaflet";

export default class extends Controller {
  static values = {
    latitude: Number,
    longitude: Number,
    zoom: Number,
    label: String
  };

  connect() {
    if (!this.latitudeValue || !this.longitudeValue) return;

    // Initialize the map
    this.map = L.map(this.element).setView(
      [this.latitudeValue, this.longitudeValue],
      this.zoomValue || 14
    );

    // === Tile Layers ===
    const baseLayers = {
      "OpenStreetMap": L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
        maxZoom: 19
      }),

      "Carto Light": L.tileLayer("https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png", {
        attribution: '&copy; <a href="https://carto.com/">CARTO</a>',
        subdomains: 'abcd',
        maxZoom: 19
      }),

      "Carto Dark": L.tileLayer("https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png", {
        attribution: '&copy; <a href="https://carto.com/">CARTO</a>',
        subdomains: 'abcd',
        maxZoom: 19
      }),

      "Stamen Toner": L.tileLayer("https://stamen-tiles.a.ssl.fastly.net/toner/{z}/{x}/{y}.png", {
        attribution: 'Map tiles by <a href="http://stamen.com">Stamen Design</a>',
        maxZoom: 20
      })
    };

    // Add default tile layer
    baseLayers["OpenStreetMap"].addTo(this.map);

    // Add layer control to switch between base maps
    L.control.layers(baseLayers).addTo(this.map);

    // Custom marker icon
    const customIcon = L.icon({
      iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
      iconSize: [32, 32],
      iconAnchor: [16, 32],
      popupAnchor: [0, -32],
      shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
      shadowSize: [36, 36]
    });

    // Add marker with popup
    L.marker([this.latitudeValue, this.longitudeValue], { icon: customIcon })
      .addTo(this.map)
      .bindPopup(this.labelValue || "Partner Location")
      .openPopup();

    // Ensure proper tile loading
    setTimeout(() => {
      this.map.invalidateSize();
    }, 200);

    // Bind resize
    this.handleResize = this.handleResize.bind(this);
    window.addEventListener('resize', this.handleResize);
  }

  handleResize() {
    if (this.map) this.map.invalidateSize();
  }

  disconnect() {
    window.removeEventListener('resize', this.handleResize);
    if (this.map) {
      this.map.remove();
      this.map = null;
    }
  }
}
