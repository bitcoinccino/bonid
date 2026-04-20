// app/javascript/controllers/scan_modal_controller.js
//
// Drives the dashboard's BonID scan modal. Two entry paths:
//
//   1. Camera button — uses Bootstrap's `data-bs-toggle="modal"` to open
//      the modal. We listen for `show.bs.modal`, fetch the scanner page,
//      and inject it into the modal body. The partner-scanner Stimulus
//      controller mounts on the injected element and starts the camera.
//
//   2. Manual entry form — its submit is intercepted (`submitManual`).
//      We append `?bonid=XXXXXX` to the URL so partner-scanner reads the
//      prefill via its data attribute, then programmatically open the modal.
//
// On `hidden.bs.modal` we wipe the frame contents so partner-scanner's
// `disconnect()` runs (`stopCamera()` releases the webcam stream).
//
// We use direct fetch + innerHTML (not <turbo-frame>) to avoid frame-
// matching/caching pitfalls that left the modal body empty.

import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = { url: String };
  static targets = ["frame", "modal"];

  connect() {
    console.log("[scan-modal] connect", {
      hasModalTarget: this.hasModalTarget,
      hasFrameTarget: this.hasFrameTarget,
      url: this.urlValue
    });
    if (!this.hasModalTarget || !this.hasFrameTarget) return;
    this._onShow = this.onShow.bind(this);
    this._onHidden = this.onHidden.bind(this);
    this.modalTarget.addEventListener("show.bs.modal", this._onShow);
    this.modalTarget.addEventListener("hidden.bs.modal", this._onHidden);
    this._initialFrameHTML =
      this.frameTarget.innerHTML?.trim() ||
      '<div class="text-center py-5 text-muted small">' +
      '<div class="spinner-border spinner-border-sm me-2" role="status"></div>' +
      'Chajman...</div>';
  }

  disconnect() {
    if (!this.hasModalTarget) return;
    this.modalTarget.removeEventListener("show.bs.modal", this._onShow);
    this.modalTarget.removeEventListener("hidden.bs.modal", this._onHidden);
  }

  // ── Bootstrap modal lifecycle ──────────────────────────────

  onShow() {
    const url = this._pendingUrl || this.urlValue;
    console.log("[scan-modal] onShow → loading", url);
    this._pendingUrl = null;
    this.loadInto(url);
  }

  onHidden() {
    // Restore initial spinner so the partner-scanner element is removed,
    // triggering its disconnect() → stopCamera() to release the webcam.
    this.frameTarget.innerHTML = this._initialFrameHTML;
  }

  // ── Fetch + inject ─────────────────────────────────────────

  async loadInto(url) {
    // Show spinner while we fetch
    this.frameTarget.innerHTML = this._initialFrameHTML;

    try {
      const resp = await fetch(url, {
        headers: { Accept: "text/html" },
        credentials: "same-origin"
      });
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      const html = await resp.text();
      console.log("[scan-modal] fetched", { status: resp.status, length: html.length });

      // The response is a full HTML page. Extract the scanner card +
      // any inline <style> and <audio> tags the page declares.
      const doc = new DOMParser().parseFromString(html, "text/html");
      const scannerNode =
        doc.querySelector("#bonid_scan_modal_frame") ||
        doc.querySelector(".scan-page");
      console.log("[scan-modal] extracted", {
        foundFrame: !!doc.querySelector("#bonid_scan_modal_frame"),
        foundScanPage: !!doc.querySelector(".scan-page"),
        scannerNodeChildren: scannerNode?.children?.length
      });

      if (!scannerNode) {
        this.frameTarget.innerHTML =
          '<div class="text-center py-5 text-danger small">Failed to load scanner.</div>';
        return;
      }

      // Build fragment: scanner content + sibling styles/audio from <body>
      this.frameTarget.innerHTML = "";
      this.frameTarget.insertAdjacentHTML("beforeend", scannerNode.innerHTML);
      doc.querySelectorAll("body > style, body > audio").forEach((el) => {
        this.frameTarget.appendChild(el.cloneNode(true));
      });
      // Stimulus's MutationObserver will auto-connect partner-scanner.
    } catch (err) {
      console.error("[scan-modal] load failed:", err);
      this.frameTarget.innerHTML =
        `<div class="text-center py-5 text-danger small">Failed to load scanner: ${err.message}</div>`;
    }
  }

  // ── Manual-entry form path ─────────────────────────────────

  submitManual(event) {
    event.preventDefault();
    const form = event.currentTarget;
    const input = form.querySelector("input[name='bonid']");
    const bonid = input?.value?.trim().toUpperCase();
    if (!bonid || bonid.length === 0) return;

    const url = new URL(this.urlValue, window.location.origin);
    url.searchParams.set("bonid", bonid);
    this._pendingUrl = url.toString();

    const Modal = window.bootstrap?.Modal;
    if (!Modal) {
      console.error("[scan-modal] Bootstrap not loaded on window.bootstrap");
      return;
    }
    Modal.getOrCreateInstance(this.modalTarget).show();
  }
}
