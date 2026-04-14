import { Controller } from "@hotwired/stimulus";
import { Html5Qrcode } from "html5-qrcode";
import * as Turbo from "@hotwired/turbo";

/**
 * Partner BonID Scanner Controller
 * Standalone scanner for non-law-enforcement partners.
 * Supports QR scan, image upload, and manual digit entry.
 */
export default class extends Controller {
  static values = {
    lookupUrl: { type: String, default: "/partner_portal/bonid_lookups" }
  };

  static targets = [
    "reader",
    "imageInput",
    "output",
    "spinner",
    "bonidInput",
    "verificationTokenInput",
    "signatureInput",
    "rescanWrapper",
    "scannerSection",
    "resultSection",
    "resultFrame",
    "deviceSelector",
    "submitButton",
    "cancelButton",
    "footer",
    "manualSection",
    "toggleHeader",
    "tipsSidebar",
    "scanGuidance",
    "guidanceText",
    "scanToast",
    "pinBox",
    "pinGroup",
    "submitLabel",
    "submitSpinner"
  ];

  connect() {
    console.log("Partner Scanner Controller connected");
    this.wasScanned = false;
    this.html5QrCode = null;
    this.cameras = [];
    this.maxRetries = 2;
    this.retryDelay = 3000;
    this.lastError = null;
    this.scanErrorCount = 0;
    this.scanToastShown = false;
    this.toastTimer = null;
    this.updateQrBoxSize();

    this.switchCamera = this.debounce(this.switchCamera.bind(this), 300);
    this.bindTurboEvents();

    // Check for ?bonid= param (from dashboard quick-entry redirect)
    const urlParams = new URLSearchParams(window.location.search);
    const prefillBonid = urlParams.get("bonid");
    if (prefillBonid && prefillBonid.trim().length > 0) {
      this.autoLookupFromParam(prefillBonid.trim().toUpperCase());
    } else {
      this.initializeScanner();
    }
  }

  // Auto-fill pin boxes and submit when redirected from dashboard with ?bonid= param
  autoLookupFromParam(bonid) {
    // Switch to manual section
    this.showManualSection();

    // Fill pin boxes with characters
    const chars = bonid.split("");
    if (this.hasPinBoxTarget) {
      this.pinBoxTargets.forEach((box, i) => {
        box.value = chars[i] || "";
      });
    }

    // Set the hidden bonid input
    if (this.hasBonidInputTarget) {
      this.bonidInputTarget.value = bonid;
    }

    // Clean up URL (remove ?bonid= so refresh doesn't re-trigger)
    const cleanUrl = window.location.pathname;
    window.history.replaceState({}, "", cleanUrl);

    // Auto-submit after a brief delay for visual feedback
    setTimeout(() => {
      this.submitForm(new Event("auto-submit"));
    }, 300);
  }

  initializeScanner() {
    this.initCameraOptions();
  }

  // ── Section Toggle ──────────────────────────────────────────

  showScannerSection(event) {
    if (event) event.preventDefault();
    this.scannerSectionTarget.classList.remove("d-none");
    this.manualSectionTarget?.classList.add("d-none");

    const scanBtn = document.getElementById("scanToggleBtn");
    const manualBtn = document.getElementById("manualToggleBtn");
    if (scanBtn) scanBtn.classList.add("active");
    if (manualBtn) manualBtn.classList.remove("active");

    this.clearOutput();
    if (!this.html5QrCode || !this.html5QrCode.isScanning) {
      this.initializeScanner();
    }
  }

  showManualSection(event) {
    if (event) event.preventDefault();
    this.manualSectionTarget?.classList.remove("d-none");
    this.scannerSectionTarget.classList.add("d-none");

    const scanBtn = document.getElementById("scanToggleBtn");
    const manualBtn = document.getElementById("manualToggleBtn");
    if (scanBtn) scanBtn.classList.remove("active");
    if (manualBtn) manualBtn.classList.add("active");

    this.clearOutput();
    this.stopCamera();
    // Auto-focus first PIN box
    setTimeout(() => {
      if (this.hasPinBoxTarget) {
        this.pinBoxTargets[0]?.focus();
      } else if (this.hasBonidInputTarget) {
        this.bonidInputTarget.focus();
      }
    }, 100);
  }

  // ── QR Box Sizing ───────────────────────────────────────────

  updateQrBoxSize() {
    if (window.innerWidth <= 576) {
      const size = Math.min(window.innerWidth * 0.9, 320);
      this.qrbox = { width: size, height: size };
    } else {
      this.qrbox = { width: 300, height: 300 };
    }
  }

  debounce(func, wait) {
    let timeout;
    return function (...args) {
      clearTimeout(timeout);
      timeout = setTimeout(() => func.apply(this, args), wait);
    };
  }

  // ── Turbo Events ────────────────────────────────────────────

  bindTurboEvents() {
    this.turboStreamRenderHandler = (event) => {
      const target = event.target;
      if (target && target.getAttribute && target.getAttribute("target") === "scan_result_frame") {
        console.log("Turbo Stream updated scan_result_frame");
        this.showResult();
        this.updateButtonVisibility();
      }
    };
    document.addEventListener("turbo:before-stream-render", this.turboStreamRenderHandler);

    // MutationObserver to detect content changes in scan_result_frame
    if (this.hasResultFrameTarget) {
      this.resultFrameObserver = new MutationObserver((mutations) => {
        for (const mutation of mutations) {
          if (mutation.type === "childList" && mutation.addedNodes.length > 0) {
            this.showResult();
            this.updateButtonVisibility();
            this.initPhotoModal();
            break;
          }
        }
      });
      this.resultFrameObserver.observe(this.resultFrameTarget, { childList: true, subtree: true });
    }
  }

  // ── Photo Modal ─────────────────────────────────────────────

  initPhotoModal() {
    document.querySelectorAll('[data-photo-enlarge]').forEach((photo) => {
      if (photo.dataset.photoModalInitialized) return;
      photo.dataset.photoModalInitialized = 'true';
      photo.addEventListener('click', this.handlePhotoClick.bind(this));
    });
  }

  handlePhotoClick(e) {
    e.preventDefault();
    const photo = e.currentTarget;
    const photoUrl = photo.dataset.photoUrl;
    const personName = photo.dataset.personName || 'Person';
    const status = photo.dataset.status || '';

    const modalImage = document.getElementById('photoModalImage');
    const modalName = document.getElementById('photoModalName');
    const statusContainer = document.getElementById('photoModalStatusContainer');
    const statusEl = document.getElementById('photoModalStatus');
    const statusIcon = document.getElementById('photoModalStatusIcon');
    const crimeInfoContainer = document.getElementById('photoModalCrimeInfo');
    // Hide crime-specific fields (not applicable for partners)
    const crimeTypeContainer = document.getElementById('photoModalCrimeTypeContainer');
    const severityContainer = document.getElementById('photoModalSeverityContainer');
    if (crimeTypeContainer) crimeTypeContainer.classList.add('d-none');
    if (severityContainer) severityContainer.classList.add('d-none');

    if (modalImage && modalName) {
      modalImage.src = photoUrl;
      modalName.textContent = personName;

      if (status && statusEl && statusContainer) {
        statusEl.textContent = status;
        let statusBadgeClass = 'bg-secondary';
        let statusIconClass = 'text-secondary';
        const statusLower = status.toLowerCase();
        if (statusLower === 'verified') {
          statusBadgeClass = 'bg-success';
          statusIconClass = 'text-success';
        } else if (statusLower === 'pending') {
          statusBadgeClass = 'bg-warning text-dark';
          statusIconClass = 'text-warning';
        } else if (statusLower === 'rejected' || statusLower === 'expired') {
          statusBadgeClass = 'bg-danger';
          statusIconClass = 'text-danger';
        }
        statusEl.className = `badge ${statusBadgeClass}`;
        statusIcon.className = `ri-shield-check-line ${statusIconClass}`;
        statusContainer.classList.remove('d-none');
        crimeInfoContainer?.classList.remove('d-none');
      } else if (statusContainer) {
        statusContainer.classList.add('d-none');
      }

      if (!status && crimeInfoContainer) {
        crimeInfoContainer.classList.add('d-none');
      }

      const modalElement = document.getElementById('photoEnlargeModal');
      if (modalElement) {
        const modal = new bootstrap.Modal(modalElement);
        modal.show();
      }
    }
  }

  // ── Disconnect ──────────────────────────────────────────────

  disconnect() {
    console.log("Partner Scanner Controller disconnected");
    this.stopCamera();
    document.removeEventListener("turbo:before-stream-render", this.turboStreamRenderHandler);
    if (this.resultFrameObserver) {
      this.resultFrameObserver.disconnect();
    }
  }

  // ── Camera ──────────────────────────────────────────────────

  async initCameraOptions() {
    this.setOutput("Requesting camera…", "info");
    this.showSpinner();

    try {
      this.cameras = await Html5Qrcode.getCameras();
      if (this.cameras.length === 0) {
        throw new Error("No cameras detected or permission denied.");
      }

      const cameraSelect = this.deviceSelectorTarget;
      cameraSelect.innerHTML = [
        `<option value="" disabled selected>Select a camera</option>`,
        ...this.cameras.map(
          (cam, i) => `<option value="${cam.id}">${cam.label || `Camera ${i + 1}`}</option>`
        )
      ].join("");

      const rearCamera =
        this.cameras.find(cam =>
          cam.label?.toLowerCase().includes("back") ||
          cam.label?.toLowerCase().includes("rear") ||
          cam.label?.toLowerCase().includes("environment")
        ) || this.cameras[0];

      await this.startCamera(rearCamera.id);
    } catch (err) {
      console.error("Camera init error:", err);
      if (err.name === "NotAllowedError" || err.message.toLowerCase().includes("permission")) {
        this.setOutput("Camera permission denied. Switching to manual lookup mode.", "warning");
        this.showManualSection();
        this.bonidInputTarget?.focus();
        return;
      }
      if (err.message.toLowerCase().includes("no cameras") || err.name === "NotFoundError") {
        this.setOutput("No camera detected. Please use manual lookup instead.", "warning");
        this.showManualSection();
        this.bonidInputTarget?.focus();
        return;
      }
      this.setOutput(`Camera unavailable. Using manual lookup.`, "warning");
      this.showManualSection();
    } finally {
      this.hideSpinner();
    }
  }

  async startCamera(cameraId) {
    await this.stopCamera();
    if (!this.html5QrCode) {
      this.html5QrCode = new Html5Qrcode(this.readerTarget.id);
    }

    const config = {
      fps: 10,
      qrbox: this.qrbox,
      disableFlip: false,
      aspectRatio: 1.0
    };

    try {
      await this.html5QrCode.start(
        cameraId,
        config,
        (decodedText) => this.handleScan(decodedText),
        (errorMsg) => this.handleError(errorMsg)
      );
      this.setOutput("Ready to scan QR code.", "info");
      this.wasScanned = false;
      this.scanErrorCount = 0;
      this.hideScanToast();
      this.setGuidance("Position QR code within the frame");

      // Remove library's built-in overlay — we use our own .scan-overlay
      const shadedRegion = document.getElementById("qr-shaded-region");
      if (shadedRegion) shadedRegion.remove();

      const tracks = this.html5QrCode?._localMediaStream?.getVideoTracks();
      const track = tracks?.[0];
      const torchToggle = document.querySelector(".torch-toggle");
      if (track?.getCapabilities().torch) {
        torchToggle?.classList.remove("d-none");
        torchToggle.querySelector("input").disabled = false;
      } else {
        torchToggle?.classList.add("d-none");
        if (torchToggle?.querySelector("input")) {
          torchToggle.querySelector("input").disabled = true;
        }
      }
    } catch (err) {
      console.error("Camera start error:", err);
      this.setOutput("Camera failed to start. Using manual lookup.", "warning");
      this.showManualSection();
    }
  }

  async stopCamera() {
    if (this.html5QrCode && this.html5QrCode.isScanning) {
      try {
        await this.html5QrCode.stop();
        await this.html5QrCode.clear();
      } catch (err) {
        console.error("Error stopping camera:", err);
      } finally {
        this.html5QrCode = null;
      }
    }
  }

  async toggleTorch(event) {
    const isOn = event.target.checked;
    const tracks = this.html5QrCode?._localMediaStream?.getVideoTracks();
    const track = tracks?.[0];

    if (!track) {
      this.setOutput("No active camera found.", "warning");
      event.target.checked = false;
      return;
    }

    if (track.getCapabilities().torch) {
      try {
        await track.applyConstraints({ advanced: [{ torch: isOn }] });
        this.setOutput(`Flashlight ${isOn ? "enabled" : "disabled"}.`, "info");
      } catch (err) {
        this.setOutput("Failed to toggle flashlight.", "warning");
        event.target.checked = false;
        event.target.disabled = true;
      }
    } else {
      this.setOutput("Flashlight not available on this camera.", "warning");
      event.target.checked = false;
      event.target.disabled = true;
    }
  }

  // ── Image Scan ──────────────────────────────────────────────

  async scanImage(event) {
    const file = event.target.files[0];
    if (!file) {
      this.setOutput("No image selected.", "danger");
      this.playSound("beep-sound-error");
      return;
    }

    const allowedTypes = ["image/png", "image/jpeg", "image/jpg"];
    if (!allowedTypes.includes(file.type)) {
      this.setOutput("Please upload a PNG or JPEG image.", "danger");
      this.playSound("beep-sound-error");
      return;
    }

    this.setOutput("Processing image...", "info");
    this.showSpinner();
    this.imageInputTarget.disabled = true;

    try {
      if (!this.html5QrCode) {
        this.html5QrCode = new Html5Qrcode(this.readerTarget.id);
      }
      const result = await this.html5QrCode.scanFile(file, true);
      if (result) {
        await this.handleScan(result);
      } else {
        this.setOutput("No QR code found in the image.", "danger");
        this.playSound("beep-sound-error");
        this.showResult();
      }
    } catch (err) {
      console.error("Image scan error:", err);
      this.setOutput(`Image processing failed: ${err.message}`, "danger");
      this.playSound("beep-sound-error");
      this.showResult();
    } finally {
      this.hideSpinner();
      this.imageInputTarget.disabled = false;
      this.imageInputTarget.value = "";
    }
  }

  // ── QR Scan Handler ─────────────────────────────────────────

  async handleScan(decodedText) {
    if (this.wasScanned) return;
    this.wasScanned = true;
    this.scanErrorCount = 0;
    this.hideScanToast();
    this.setGuidance("QR code detected!");
    this.setOutput("Verifying ID…", "info");
    this.showSpinner();

    try {
      let payload;

      // Try to parse as JSON first (BonID QR format)
      try {
        const parsed = JSON.parse(decodedText);

        if (parsed.v === 2 && parsed.sub && parsed.sig) {
          // Ed25519 v2 QR payload: { v, iss, typ, sub, ts, exp, sig }
          // Send the full raw JSON so the server can verify the Ed25519 signature
          payload = { bonid: parsed.sub, qr_payload: decodedText };
        } else if (parsed.bonid && parsed.timestamp && parsed.signature) {
          // Legacy HMAC QR payload: { bonid, timestamp, signature }
          payload = parsed;
        } else if (parsed.sub) {
          // Minimal payload with subject
          payload = { bonid: parsed.sub, timestamp: "", signature: "" };
        } else {
          throw new Error("Unrecognized JSON QR format.");
        }
      } catch (jsonErr) {
        // Check if it's a BonTouris verification URL
        const bonTourisUrlRegex = /[?&]payload=([A-Za-z0-9_-]+)/;
        const urlMatch = decodedText.match(bonTourisUrlRegex);

        if (urlMatch) {
          try {
            const payloadStr = atob(urlMatch[1].replace(/-/g, '+').replace(/_/g, '/'));
            const payloadData = JSON.parse(payloadStr);
            if (payloadData.sub) {
              payload = { bonid: payloadData.sub, timestamp: "", signature: "" };
            } else {
              throw new Error("Missing 'sub' in BonTouris payload");
            }
          } catch (decodeErr) {
            throw new Error("Invalid BonTouris QR code format.");
          }
        } else {
          // Check if it's a raw BonID or BonTouris ID string
          // Citizen BonID: DV-1989-M-SE-P8697XDS
          const bonidRegex = /^[A-Z]{2}-\d{4}-[A-Z]-[A-Z]+-[A-Z]\d{4}[A-Z0-9]{3}$/i;
          const bonTourisRegex = /^T-[A-Z]{2,3}-\d{4}-[A-Z]-[A-Z]{2,3}-P-\d{6}$/i;

          if (bonidRegex.test(decodedText) || bonTourisRegex.test(decodedText)) {
            payload = { bonid: decodedText, timestamp: "", signature: "" };
          } else {
            throw new Error("Invalid QR code format.");
          }
        }
      }

      const formData = new FormData();
      formData.append("bonid_lookup[bonid]", payload.bonid);
      if (payload.qr_payload) formData.append("bonid_lookup[qr_payload]", payload.qr_payload);
      if (payload.timestamp) formData.append("bonid_lookup[timestamp]", payload.timestamp);
      if (payload.signature) formData.append("bonid_lookup[signature]", payload.signature);
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
      if (!csrfToken) throw new Error("CSRF token missing.");
      formData.append("bonid_lookup[authenticity_token]", csrfToken);

      const response = await fetch(this.lookupUrlValue, {
        method: "POST",
        headers: { Accept: "text/vnd.turbo-stream.html" },
        body: formData
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`Server error: ${response.status} - ${errorText}`);
      }

      const html = await response.text();
      if (html.includes("turbo-stream")) {
        Turbo.renderStreamMessage(html);
        const isBonTouris = html.includes("visitor_valid") || html.includes("BonTouris");
        this.setOutput(isBonTouris ? "BonTouris verified." : "BonID verified.", "success");
        this.playSound("beep-sound-success");
      } else {
        this.setOutput("Unexpected server response. Please try again.", "danger");
        this.playSound("beep-sound-error");
      }

      this.showResult();
      await this.stopCamera();
    } catch (err) {
      console.error("Scan verification error:", err);
      this.setOutput(`Verification failed: ${err.message}`, "danger");
      this.playSound("beep-sound-error");
      this.showResult();
    } finally {
      this.hideSpinner();
    }
  }

  // ── PIN Input (6-box segmented) ─────────────────────────────

  pinInput(event) {
    const box = event.target;
    const value = box.value.replace(/[^A-Za-z0-9]/g, "").toUpperCase();
    box.value = value;
    box.classList.toggle("filled", value.length > 0);

    // Advance to next box
    if (value && parseInt(box.dataset.index) < 5) {
      const nextIndex = parseInt(box.dataset.index) + 1;
      const next = this.pinBoxTargets[nextIndex];
      if (next) next.focus();
    }

    this.syncPinToHiddenInput();
  }

  pinKeydown(event) {
    const box = event.target;
    const idx = parseInt(box.dataset.index);

    if (event.key === "Backspace") {
      if (!box.value && idx > 0) {
        event.preventDefault();
        const prev = this.pinBoxTargets[idx - 1];
        if (prev) { prev.value = ""; prev.classList.remove("filled"); prev.focus(); }
      } else {
        box.classList.remove("filled");
      }
      setTimeout(() => this.syncPinToHiddenInput(), 0);
    }

    if (event.key === "ArrowLeft" && idx > 0) {
      event.preventDefault();
      this.pinBoxTargets[idx - 1]?.focus();
    }
    if (event.key === "ArrowRight" && idx < 5) {
      event.preventDefault();
      this.pinBoxTargets[idx + 1]?.focus();
    }

    if (event.key === "Enter") {
      event.preventDefault();
      this.submitForm(event);
    }
  }

  pinPaste(event) {
    event.preventDefault();
    const pasted = (event.clipboardData?.getData("text") || "")
      .replace(/[^A-Za-z0-9]/g, "")
      .toUpperCase()
      .slice(0, 6);

    pasted.split("").forEach((char, i) => {
      if (this.pinBoxTargets[i]) {
        this.pinBoxTargets[i].value = char;
        this.pinBoxTargets[i].classList.toggle("filled", char.length > 0);
      }
    });

    const focusIdx = Math.min(pasted.length, 5);
    this.pinBoxTargets[focusIdx]?.focus();
    this.syncPinToHiddenInput();
  }

  syncPinToHiddenInput() {
    if (!this.hasBonidInputTarget || !this.hasPinBoxTarget) return;
    const combined = this.pinBoxTargets.map(b => b.value).join("");
    this.bonidInputTarget.value = combined;
  }

  clearPinBoxes() {
    if (!this.hasPinBoxTarget) return;
    this.pinBoxTargets.forEach(box => { box.value = ""; box.classList.remove("filled"); });
    if (this.hasBonidInputTarget) this.bonidInputTarget.value = "";
  }

  // ── Manual Entry ────────────────────────────────────────────

  validateBonidInput(event) {
    const bonid = event.target.value.trim();
    const digitOnlyRegex = /^[A-Z0-9]{6}$/i;
    const fullBonidRegex = /^[A-Z]{2}-\d{4}-[A-Z]-[A-Z]+-[A-Z]\d{4}[A-Z0-9]{3}$/i;
    const visitorSuffixRegex = /^P-\d{6}$/i;
    const fullBonTourisRegex = /^T-[A-Z]{2,3}-\d{4}-[A-Z]-[A-Z]{2,3}-P-\d{6}$/i;

    const isValid = digitOnlyRegex.test(bonid) ||
                    fullBonidRegex.test(bonid) ||
                    visitorSuffixRegex.test(bonid) ||
                    fullBonTourisRegex.test(bonid);

    if (bonid && !isValid) {
      this.setOutput("Enter last 6 characters (e.g. 697XDS)", "warning");
    } else {
      this.clearOutput();
    }
  }

  submitForm(event) {
    event.preventDefault();
    const bonid = this.bonidInputTarget.value.trim();
    const digitOnlyRegex = /^[A-Z0-9]{6}$/i;
    const fullBonidRegex = /^[A-Z]{2}-\d{4}-[A-Z]-[A-Z]+-[A-Z]\d{4}[A-Z0-9]{3}$/i;
    const visitorSuffixRegex = /^P-\d{6}$/i;
    const fullBonTourisRegex = /^T-[A-Z]{2,3}-\d{4}-[A-Z]-[A-Z]{2,3}-P-\d{6}$/i;

    if (!bonid) {
      this.setOutput("Please enter the last 6 characters of the BonID.", "danger");
      this.playSound("beep-sound-error");
      return;
    }

    const isValid = digitOnlyRegex.test(bonid) ||
                    fullBonidRegex.test(bonid) ||
                    visitorSuffixRegex.test(bonid) ||
                    fullBonTourisRegex.test(bonid);

    if (!isValid) {
      this.setOutput("Enter last 6 characters of the BonID", "danger");
      this.playSound("beep-sound-error");
      return;
    }

    if (digitOnlyRegex.test(bonid)) {
      this.setOutput("Searching for citizen or tourist...", "info");
    } else if (visitorSuffixRegex.test(bonid)) {
      this.setOutput("Looking up tourist...", "info");
    } else {
      this.setOutput("Looking up ID…", "info");
    }

    this.showSpinner();
    this.submitButtonTarget.disabled = true;
    this.showSubmitSpinner(true);

    const formData = new FormData();
    formData.append("bonid_lookup[bonid]", bonid);
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
    if (csrfToken) {
      formData.append("bonid_lookup[authenticity_token]", csrfToken);
    } else {
      this.setOutput("Submission failed: CSRF token missing.", "danger");
      this.hideSpinner();
      this.submitButtonTarget.disabled = false;
      this.showSubmitSpinner(false);
      return;
    }

    fetch(this.lookupUrlValue, {
      method: "POST",
      headers: { Accept: "text/vnd.turbo-stream.html" },
      body: formData
    })
      .then(resp => {
        if (!resp.ok) {
          return resp.text().then(errorText => {
            throw new Error(`Server error: ${resp.status} - ${errorText}`);
          });
        }
        return resp.text();
      })
      .then(html => {
        if (html.includes("turbo-stream")) {
          Turbo.renderStreamMessage(html);
          this.clearOutput();
          this.playSound("beep-sound-success");
          this.showResult();
        } else {
          throw new Error("Unexpected server response.");
        }
      })
      .catch(err => {
        console.error("Submit error:", err);
        this.setOutput(`Submit failed: ${err.message}`, "danger");
        this.playSound("beep-sound-error");
        this.showResult();
      })
      .finally(() => {
        this.hideSpinner();
        this.submitButtonTarget.disabled = false;
        this.showSubmitSpinner(false);
      });
  }

  // ── Identity Confirmation ───────────────────────────────────

  confirmIdentity(event) {
    event.preventDefault();
    const button = event.currentTarget;
    const url = button.dataset.confirmUrl;
    const confirmed = button.dataset.confirmed;

    if (!url) {
      this.setOutput("Confirmation failed: missing URL", "danger");
      return;
    }

    const originalHtml = button.innerHTML;
    button.disabled = true;
    button.innerHTML = '<i class="ri-loader-4-line" style="animation: spin 1s linear infinite;"></i> Processing...';

    const formData = new FormData();
    formData.append("confirmed", confirmed);
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
    if (csrfToken) formData.append("authenticity_token", csrfToken);

    fetch(url, {
      method: "POST",
      headers: { Accept: "text/vnd.turbo-stream.html" },
      body: formData
    })
      .then(resp => {
        if (!resp.ok) throw new Error(`Server error: ${resp.status}`);
        return resp.text();
      })
      .then(html => {
        if (html.includes("turbo-stream")) {
          Turbo.renderStreamMessage(html);
          if (confirmed === "true") {
            this.setOutput("Identity confirmed.", "success");
            this.playSound("beep-sound-success");
          } else {
            this.setOutput("Identity mismatch reported.", "warning");
          }
        } else {
          throw new Error("Unexpected server response.");
        }
      })
      .catch(err => {
        console.error("Confirmation error:", err);
        this.setOutput(`Confirmation failed: ${err.message}`, "danger");
        this.playSound("beep-sound-error");
        button.disabled = false;
        button.innerHTML = originalHtml;
      });
  }

  // ── Cancel / Rescan ─────────────────────────────────────────

  cancel(event) {
    event.preventDefault();
    window.location.href = "/partner_portal/dashboard";
  }

  rescan() {
    console.log("Rescan triggered");
    // Reset everything and restart the scanner on this page
    this.reset();

    // Clear the reader div so html5-qrcode can reinitialize cleanly
    if (this.hasReaderTarget) {
      this.readerTarget.innerHTML = "";
    }
    this.html5QrCode = null;

    this.showScannerSection();
    this.initializeScanner();
  }

  reset() {
    this.stopCamera();
    this.wasScanned = false;
    this.cameras = [];
    this.lastError = null;
    this.scanErrorCount = 0;
    this.clearOutput();
    this.hideSpinner();
    this.hideScanToast();

    if (this.hasRescanWrapperTarget) this.rescanWrapperTarget.classList.add("d-none");
    this.clearPinBoxes();
    if (this.hasBonidInputTarget) {
      this.bonidInputTarget.value = "";
      this.bonidInputTarget.classList.remove("d-none");
    }
    if (this.hasVerificationTokenInputTarget) {
      this.verificationTokenInputTarget.value = "";
      this.verificationTokenInputTarget.classList.remove("d-none");
    }
    if (this.hasSignatureInputTarget) {
      this.signatureInputTarget.value = "";
      this.signatureInputTarget.classList.remove("d-none");
    }
    if (this.hasImageInputTarget) this.imageInputTarget.value = "";
    if (this.hasSubmitButtonTarget) this.submitButtonTarget.disabled = false;
    if (this.hasFooterTarget) this.footerTarget.classList.remove("d-none");
    if (this.hasToggleHeaderTarget) this.toggleHeaderTarget.classList.remove("d-none");
    if (this.hasTipsSidebarTarget) this.tipsSidebarTarget.classList.remove("tips-hidden");

    if (this.hasResultFrameTarget && this.hasScannerSectionTarget && this.hasResultSectionTarget) {
      this.resultFrameTarget.innerHTML = '<div class="text-center text-muted small">Scan result will appear here.</div>';
      this.resultFrameTarget.setAttribute("data-result-type", "");
      this.resultSectionTarget.classList.add("d-none");
      this.scannerSectionTarget.classList.remove("d-none");
    }
  }

  // ── UI Helpers ──────────────────────────────────────────────

  showResult() {
    if (this.hasResultSectionTarget) {
      this.resultSectionTarget.classList.remove("d-none");
      if (this.hasScannerSectionTarget) this.scannerSectionTarget.classList.add("d-none");
      if (this.hasManualSectionTarget) this.manualSectionTarget.classList.add("d-none");
      if (this.hasToggleHeaderTarget) this.toggleHeaderTarget.classList.add("d-none");
      if (this.hasFooterTarget) this.footerTarget.classList.add("d-none");
      this.updateButtonVisibility();
    }
    this.wasScanned = false;
  }

  updateButtonVisibility() {
    // data-result-type is on the child element rendered by Turbo Stream
    const child = this.resultFrameTarget?.querySelector("[data-result-type]");
    const resultType = child?.getAttribute("data-result-type") || "";
    const isSuccess = resultType === "valid" || resultType === "visitor_valid";
    const isPending = resultType === "pending_confirmation";
    const hideChrome = isSuccess || isPending;

    if (this.hasRescanWrapperTarget) {
      // Show rescan wrapper for error states (success/pending cards have their own buttons)
      this.rescanWrapperTarget.classList.toggle("d-none", hideChrome);
    }
    if (this.hasFooterTarget) {
      this.footerTarget.classList.toggle("d-none", hideChrome);
    }

    // Hide tips sidebar for success and pending confirmation views
    if (this.hasTipsSidebarTarget) {
      if (hideChrome) {
        this.tipsSidebarTarget.classList.add("tips-hidden");
      } else {
        this.tipsSidebarTarget.classList.remove("tips-hidden");
      }
    }
  }

  setOutput(message, status = "info") {
    if (!this.hasOutputTarget) return;
    this.outputTarget.textContent = message;
    this.outputTarget.className = `alert alert-${status} text-center small ${message ? "" : "d-none"}`;
    this.outputTarget.setAttribute("aria-live", "polite");
  }

  clearOutput() {
    if (this.hasOutputTarget) {
      this.outputTarget.classList.add("d-none");
      this.outputTarget.textContent = "";
    }
  }

  showSpinner() {
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.remove("d-none");
      this.spinnerTarget.setAttribute("aria-busy", "true");
    }
  }

  hideSpinner() {
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.add("d-none");
      this.spinnerTarget.setAttribute("aria-busy", "false");
    }
  }

  playSound(soundId) {
    const audio = document.getElementById(soundId);
    if (audio) {
      audio.play().catch(() => {});
    }
  }

  handleError(errorMsg) {
    if (this.hasScannerSectionTarget && this.scannerSectionTarget.classList.contains("d-none")) return;

    // Update real-time guidance based on error patterns
    if (this.hasGuidanceTextTarget) {
      const msg = errorMsg.toLowerCase();
      if (msg.includes("no qr code") || msg.includes("no multi-format")) {
        this.scanErrorCount++;
        if (this.scanErrorCount > 20) {
          this.setGuidance("Move closer to the QR code");
        } else if (this.scanErrorCount > 10) {
          this.setGuidance("Hold steady \u2014 scanning...");
        }
      } else if (msg.includes("dimensions") || msg.includes("too small")) {
        this.setGuidance("Move closer to the QR code");
      }
    }

    // Show toast after ~5s of continuous failure (fps=10, ~50 errors)
    if (!this.scanToastShown && this.scanErrorCount > 50) {
      this.showScanToast();
    }

    if (this.lastError === errorMsg) return;
    this.lastError = errorMsg;
  }

  setGuidance(text) {
    if (this.hasGuidanceTextTarget) {
      this.guidanceTextTarget.textContent = text;
    }
  }

  showScanToast() {
    if (this.scanToastShown) return;
    this.scanToastShown = true;
    if (this.hasScanToastTarget) {
      this.scanToastTarget.classList.remove("d-none");
    }
  }

  showSubmitSpinner(show) {
    if (this.hasSubmitLabelTarget) this.submitLabelTarget.classList.toggle("d-none", show);
    if (this.hasSubmitSpinnerTarget) this.submitSpinnerTarget.classList.toggle("d-none", !show);
  }

  hideScanToast() {
    this.scanToastShown = false;
    this.scanErrorCount = 0;
    if (this.hasScanToastTarget) {
      this.scanToastTarget.classList.add("d-none");
    }
  }

  async retryOperation(operation, name) {
    let attempt = 0;
    while (attempt <= this.maxRetries) {
      try {
        await operation();
        break;
      } catch (err) {
        attempt++;
        if (attempt > this.maxRetries) {
          this.setOutput(`${name} failed after ${this.maxRetries} attempts.`, "danger");
        } else {
          this.setOutput(`${name} retrying… (${attempt}/${this.maxRetries})`, "warning");
          await this.sleep(this.retryDelay * Math.pow(2, attempt));
        }
      }
    }
  }

  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  async switchCamera(event) {
    const cameraId = event.target.value;
    if (!cameraId || cameraId === this.html5QrCode?.getRunningTrackCameraId()) return;
    await this.startCamera(cameraId);
  }
}
