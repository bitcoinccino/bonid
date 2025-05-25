import { Controller } from "@hotwired/stimulus";
import { Html5QrcodeScanner } from "html5-qrcode";

// Connects to data-controller="qr-scanner"
export default class extends Controller {
  static targets = ["output"];

  connect() {
    this.scanner = new Html5QrcodeScanner("qr-reader", {
      fps: 10,
      qrbox: 250,
      rememberLastUsedCamera: true,
      aspectRatio: 1.7777778
    });

    this.scanner.render(this.handleScan.bind(this), this.handleError.bind(this));
  }

  disconnect() {
    if (this.scanner?.clear) {
      this.scanner.clear().catch(console.warn);
    }
  }

  async handleScan(decodedText) {
    try {
      const payload = JSON.parse(decodedText);

      const response = await fetch("/officer/scan", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("[name='csrf-token']").content,
        },
        body: JSON.stringify({ qr_data: payload }),
      });

      const result = await response.json();

      if (response.ok) {
        this.outputTarget.innerHTML = `<strong>${result.name}</strong><br>${result.bonid}`;
        window.location.href = `/officer/reports/new?bonid=${result.bonid}`;
      } else {
        this.outputTarget.innerHTML = `<span class="text-danger">${result.error}</span>`;
      }
    } catch (e) {
      this.outputTarget.innerHTML = `<span class="text-danger">Invalid QR format</span>`;
    }
  }

  handleError(errorMessage) {
    console.warn("QR Scan error:", errorMessage);
  }
}
