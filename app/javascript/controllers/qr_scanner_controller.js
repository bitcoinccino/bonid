import { Controller } from "@hotwired/stimulus";
import { Html5Qrcode } from "html5-qrcode";
import * as Turbo from "@hotwired/turbo";

export default class extends Controller {
  static values = {
    lookupUrl: { type: String, default: "/officers/bonid_lookups" }
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
    "toggleHeader"
  ];

  connect() {
    console.log("QR Scanner Controller connected");
    this.wasScanned = false;
    this.html5QrCode = null;
    this.cameras = [];
    this.maxRetries = 2;
    this.retryDelay = 3000;
    this.modalEl = null;
    this.modalShowHandler = null;
    this.modalHideHandler = null;
    this.turboRenderHandler = null;
    this.turboFrameRenderHandler = null;
    this.lastError = null;
    this._initializing = false;
    this.updateQrBoxSize();

    this.switchCamera = this.debounce(this.switchCamera.bind(this), 300);
    this.bindModalEvents();
    this.bindTurboEvents();

    // Auto-initialize scanner if not in modal (standalone page)
    if (!this.modalEl) {
      this.initializeScanner();
    }
  }

  initializeScanner() {
    this.initCameraOptions();
  }

  showScannerSection(event) {
    console.log("showScannerSection called");
    if (event) event.preventDefault();

    this.scannerSectionTarget.classList.remove("d-none");
    this.manualSectionTarget?.classList.add("d-none");

    // Update toggle button active state (CSS handles styling)
    const scanBtn = document.getElementById("scanToggleBtn");
    const manualBtn = document.getElementById("manualToggleBtn");

    if (scanBtn) scanBtn.classList.add("active");
    if (manualBtn) manualBtn.classList.remove("active");

    this.clearOutput();

    // Restart camera when switching back to scan mode
    if (!this.html5QrCode || !this.html5QrCode.isScanning) {
      this.initializeScanner();
    }
  }

  showManualSection(event) {
    console.log("showManualSection called");
    if (event) event.preventDefault();

    this.manualSectionTarget?.classList.remove("d-none");
    this.scannerSectionTarget.classList.add("d-none");

    // Update toggle button active state (CSS handles styling)
    const scanBtn = document.getElementById("scanToggleBtn");
    const manualBtn = document.getElementById("manualToggleBtn");

    if (scanBtn) scanBtn.classList.remove("active");
    if (manualBtn) manualBtn.classList.add("active");

    this.clearOutput();
    // Stop camera when switching to manual entry
    this.stopCamera();
    // Focus the input field for quick entry
    setTimeout(() => {
      this.bonidInputTarget?.focus();
    }, 100);
  }

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

  bindModalEvents() {
    this.modalEl = document.getElementById("bonidScanModal");
    if (this.modalEl) {
      this.modalShowHandler = () => {
        console.log("Modal shown, initializing scanner");
        this.initializeScanner();
        document.getElementById("beep-sound-success")?.load();
        document.getElementById("beep-sound-error")?.load();
      };
      this.modalHideHandler = () => {
        console.log("Modal hidden, resetting");
        this.reset();
      };
      this.modalEl.addEventListener("shown.bs.modal", this.modalShowHandler);
      this.modalEl.addEventListener("hidden.bs.modal", this.modalHideHandler);
    }
    // Standalone page (no modal) is a valid use case — scanner auto-initializes in connect()
  }

  bindTurboEvents() {
    this.turboRenderHandler = () => {
      console.log("Turbo render, re-binding modal events");
      this.removeModalEvents();
      this.bindModalEvents();
    };
    this.turboFrameRenderHandler = (event) => {
      // Note: scan_result_frame is now a regular div, not a turbo-frame
      // This handler kept for any other turbo-frame interactions
      console.log("Turbo frame rendered");
    };
    // Listen for Turbo Stream updates to the scan_result_frame
    this.turboStreamRenderHandler = (event) => {
      const target = event.target;
      if (target && target.getAttribute && target.getAttribute("target") === "scan_result_frame") {
        console.log("Turbo Stream updated scan_result_frame");
        this.showResult();
        this.updateButtonVisibility();
      }
    };
    document.addEventListener("turbo:render", this.turboRenderHandler);
    document.addEventListener("turbo:frame-render", this.turboFrameRenderHandler);
    document.addEventListener("turbo:before-stream-render", this.turboStreamRenderHandler);

    // MutationObserver to detect content changes in scan_result_frame
    if (this.hasResultFrameTarget) {
      this.resultFrameObserver = new MutationObserver((mutations) => {
        for (const mutation of mutations) {
          if (mutation.type === "childList" && mutation.addedNodes.length > 0) {
            console.log("MutationObserver: scan_result_frame content changed");
            this.showResult();
            this.updateButtonVisibility();
            // Initialize photo modal for enlarged photo viewing
            this.initPhotoModal();
            break;
          }
        }
      });
      this.resultFrameObserver.observe(this.resultFrameTarget, { childList: true, subtree: true });
    }
  }

  // Initialize photo modal functionality for scan results
  initPhotoModal() {
    // Find all clickable photos and attach event listeners
    document.querySelectorAll('[data-photo-enlarge]').forEach((photo) => {
      if (photo.dataset.photoModalInitialized) return; // Skip if already initialized
      photo.dataset.photoModalInitialized = 'true';
      photo.addEventListener('click', this.handlePhotoClick.bind(this));
    });
  }

  handlePhotoClick(e) {
    e.preventDefault();
    const photo = e.currentTarget;
    const photoUrl = photo.dataset.photoUrl;
    const personName = photo.dataset.personName || 'Person';
    const crimeType = photo.dataset.crimeType || '';
    const severityLevel = photo.dataset.severityLevel || '';
    const status = photo.dataset.status || '';

    // Update modal content
    const modalImage = document.getElementById('photoModalImage');
    const modalName = document.getElementById('photoModalName');
    const crimeInfoContainer = document.getElementById('photoModalCrimeInfo');
    const statusContainer = document.getElementById('photoModalStatusContainer');
    const statusEl = document.getElementById('photoModalStatus');
    const statusIcon = document.getElementById('photoModalStatusIcon');
    const crimeTypeContainer = document.getElementById('photoModalCrimeTypeContainer');
    const crimeTypeEl = document.getElementById('photoModalCrimeType');
    const severityContainer = document.getElementById('photoModalSeverityContainer');
    const severityEl = document.getElementById('photoModalSeverity');
    const severityIcon = document.getElementById('photoModalSeverityIcon');

    if (modalImage && modalName) {
      modalImage.src = photoUrl;
      modalName.textContent = personName;

      // Handle status display
      if (status && statusEl && statusContainer) {
        statusEl.textContent = status;
        let statusBadgeClass = 'bg-secondary';
        let statusIconClass = 'text-secondary';

        // Set badge color based on status
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

      // Handle crime type display
      if (crimeType && crimeTypeEl && crimeTypeContainer) {
        crimeTypeEl.textContent = crimeType;
        crimeTypeContainer.classList.remove('d-none');
        crimeInfoContainer?.classList.remove('d-none');
      } else if (crimeTypeContainer) {
        crimeTypeContainer.classList.add('d-none');
      }

      // Handle severity level display
      if (severityLevel && severityEl && severityContainer) {
        const level = parseInt(severityLevel, 10);
        let severityText = '';
        let badgeClass = '';
        let iconClass = '';

        switch(level) {
          case 5:
            severityText = 'Critical (5)';
            badgeClass = 'bg-danger';
            iconClass = 'text-danger';
            break;
          case 4:
            severityText = 'Severe (4)';
            badgeClass = 'bg-danger';
            iconClass = 'text-danger';
            break;
          case 3:
            severityText = 'High (3)';
            badgeClass = 'bg-warning text-dark';
            iconClass = 'text-warning';
            break;
          case 2:
            severityText = 'Medium (2)';
            badgeClass = 'bg-info';
            iconClass = 'text-info';
            break;
          case 1:
            severityText = 'Low (1)';
            badgeClass = 'bg-secondary';
            iconClass = 'text-secondary';
            break;
          default:
            severityText = `Level ${level}`;
            badgeClass = 'bg-secondary';
            iconClass = 'text-secondary';
        }

        severityEl.textContent = severityText;
        severityEl.className = `badge ${badgeClass}`;
        severityIcon.className = `ri-bar-chart-fill ${iconClass}`;
        severityContainer.classList.remove('d-none');
        crimeInfoContainer?.classList.remove('d-none');
      } else if (severityContainer) {
        severityContainer.classList.add('d-none');
      }

      // Hide crime info container if all are empty
      if (!status && !crimeType && !severityLevel && crimeInfoContainer) {
        crimeInfoContainer.classList.add('d-none');
      }

      // Show modal
      const modalElement = document.getElementById('photoEnlargeModal');
      if (modalElement) {
        const modal = new bootstrap.Modal(modalElement);
        modal.show();
      }
    }
  }

  removeModalEvents() {
    if (this.modalEl) {
      this.modalEl.removeEventListener("shown.bs.modal", this.modalShowHandler);
      this.modalEl.removeEventListener("hidden.bs.modal", this.modalHideHandler);
    }
  }

  disconnect() {
    console.log("QR Scanner Controller disconnected");
    this._initializing = false;
    // Synchronously clear video elements to prevent duplication on reconnect
    if (this.hasReaderTarget) this.readerTarget.innerHTML = "";
    this.stopCamera();
    this.removeModalEvents();
    document.removeEventListener("turbo:render", this.turboRenderHandler);
    document.removeEventListener("turbo:frame-render", this.turboFrameRenderHandler);
    document.removeEventListener("turbo:before-stream-render", this.turboStreamRenderHandler);
    if (this.resultFrameObserver) {
      this.resultFrameObserver.disconnect();
    }
  }

  async initCameraOptions() {
    if (this._initializing) return; // prevent re-entrance
    this._initializing = true;

    this.setOutput("Requesting camera\u2026", "info");
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

      // ✅ Graceful fallback if camera access fails
      if (err.name === "NotAllowedError" || err.message.toLowerCase().includes("permission")) {
        this.setOutput(
          "Camera permission denied. Switching to manual lookup mode.",
          "warning"
        );
        this.showManualSection();
        // Autofocus the manual input for quick entry
        this.bonidInputTarget?.focus();
        return;
      }

      // ✅ Handle "no camera found"
      if (err.message.toLowerCase().includes("no cameras") || err.name === "NotFoundError") {
        this.setOutput(
          "No camera detected. Please use manual lookup instead.",
          "warning"
        );
        this.showManualSection();
        this.bonidInputTarget?.focus();
        return;
      }

      // ✅ Generic fallback
      this.setOutput(`Camera error: ${err.message}`, "danger");
      this.showResult();
      await this.retryOperation(() => this.initCameraOptions(), "Camera initialization");
    } finally {
      this._initializing = false;
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

      const tracks = this.html5QrCode?._localMediaStream?.getVideoTracks();
      const track = tracks?.[0];
      const torchToggle = document.querySelector(".torch-toggle");
      if (track?.getCapabilities().torch) {
        console.log("Torch supported, showing toggle");
        torchToggle?.classList.remove("d-none");
        torchToggle.querySelector("input").disabled = false;
      } else {
        console.log("Torch not supported on this camera");
        torchToggle?.classList.add("d-none");
        torchToggle.querySelector("input").disabled = true;
      }
    } catch (err) {
      console.error("Camera start error:", err);
      if (err.name === "NotFoundError") {
        this.setOutput("Camera not found. Please ensure a camera is available.", "danger");
      } else {
        this.setOutput(`Failed to start camera: ${err.message}`, "danger");
      }
      this.showResult();
      await this.retryOperation(() => this.startCamera(cameraId), "Camera start");
    }
  }

  async stopCamera() {
    if (this.html5QrCode) {
      try {
        if (this.html5QrCode.isScanning) {
          await this.html5QrCode.stop();
        }
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
      console.log("No active camera found for torch toggle");
      this.setOutput("No active camera found.", "warning");
      event.target.checked = false;
      return;
    }

    if (track.getCapabilities().torch) {
      try {
        await track.applyConstraints({ advanced: [{ torch: isOn }] });
        this.setOutput(`Flashlight ${isOn ? "enabled" : "disabled"}.`, "info");
      } catch (err) {
        console.error("Torch toggle error:", err);
        this.setOutput("Failed to toggle flashlight.", "warning");
        event.target.checked = false;
        event.target.disabled = true;
      }
    } else {
      console.log("Torch not available on this camera");
      this.setOutput("Flashlight not available on this camera.", "warning");
      event.target.checked = false;
      event.target.disabled = true;
    }
  }

  async scanImage(event) {
    const file = event.target.files[0];
    if (!file) {
      console.log("No file selected for image scan");
      this.setOutput("No image selected.", "danger");
      this.playSound("beep-sound-error");
      return;
    }

    const allowedTypes = ["image/png", "image/jpeg", "image/jpg"];
    if (!allowedTypes.includes(file.type)) {
      console.log("Invalid file type:", file.type);
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
        console.log("QR code detected in image:", result);
        await this.handleScan(result);
      } else {
        console.log("No QR code found in image");
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

  async handleScan(decodedText) {
    if (this.wasScanned) return;
    this.wasScanned = true;
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
        // Not JSON - check other formats

        // Check if it's a BonTouris verification URL: /v?payload=...
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
          // BonTouris (tourist): T-JM-1990-M-US-P-123456
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
      console.log("Received server response:", html);
      if (html.includes("turbo-stream")) {
        // Process Turbo Stream response properly
        Turbo.renderStreamMessage(html);
        // Check if this is a BonTouris (visitor) or BonID (citizen) verification
        const isBonTouris = html.includes("visitor_valid") || html.includes("BonTouris");
        this.setOutput(isBonTouris ? "BonTouris verified." : "BonID verified.", "success");
        this.playSound("beep-sound-success");
      } else {
        console.warn("Non-Turbo response received:", html);
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

  validateBonidInput(event) {
    const bonid = event.target.value.trim();

    // New simplified 6-7 digit format (primary)
    // Citizens: 7 digits (XXXX-XXX format = 4+3)
    // Tourists: 6 digits (passport last 6)
    const digitOnlyRegex = /^[A-Z0-9]{6}$/i;

    // Legacy formats for backward compatibility
    // Full BonID (citizen): DV-1989-M-SE-P8697XDS
    const fullBonidRegex = /^[A-Z]{2}-\d{4}-[A-Z]-[A-Z]+-[A-Z]\d{4}[A-Z0-9]{3}$/i;
    // BonTouris suffix: P-123456 (P + exactly 6 digits - passport last 6)
    const visitorSuffixRegex = /^P-\d{6}$/i;
    // Full BonTouris: T-JM-1990-M-US-P-123456
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

  // Check if input is simplified 6-char format (last 6 of BonID suffix)
  isDigitOnlyFormat(input) {
    return /^[A-Z0-9]{6}$/i.test(input);
  }

  // Check if input is BonTouris/visitor suffix format (P-NNNNNN - 6 digits)
  isVisitorSuffixFormat(input) {
    return /^P-\d{6}$/i.test(input);
  }

  submitForm(event) {
    console.log("Submit button clicked, processing manual input");
    event.preventDefault();
    const bonid = this.bonidInputTarget.value.trim();

    // New simplified 6-char format (primary)
    // Last 6 alphanumeric chars of the BonID suffix
    const digitOnlyRegex = /^[A-Z0-9]{6}$/i;

    // Legacy formats for backward compatibility
    // Full BonID (citizen): DV-1989-M-SE-P8697XDS
    const fullBonidRegex = /^[A-Z]{2}-\d{4}-[A-Z]-[A-Z]+-[A-Z]\d{4}[A-Z0-9]{3}$/i;
    // BonTouris suffix: P-123456 (P + exactly 6 digits - passport last 6)
    const visitorSuffixRegex = /^P-\d{6}$/i;
    // Full BonTouris: T-JM-1990-M-US-P-123456
    const fullBonTourisRegex = /^T-[A-Z]{2,3}-\d{4}-[A-Z]-[A-Z]{2,3}-P-\d{6}$/i;

    if (!bonid) {
      this.setOutput("Please enter last 6 characters.", "danger");
      this.playSound("beep-sound-error");
      return;
    }

    const isValid = digitOnlyRegex.test(bonid) ||
                    fullBonidRegex.test(bonid) ||
                    visitorSuffixRegex.test(bonid) ||
                    fullBonTourisRegex.test(bonid);

    if (!isValid) {
      console.log("Invalid format:", bonid);
      this.setOutput("Enter 6-7 digits (Citizens: 7, Tourists: 6)", "danger");
      this.playSound("beep-sound-error");
      return;
    }

    // Inform user based on lookup type
    if (this.isDigitOnlyFormat(bonid)) {
      this.setOutput("Searching for citizen or tourist...", "info");
    } else if (this.isCitizenSuffixFormat(bonid)) {
      this.setOutput("Looking up citizen (requires visual verification)...", "info");
    } else if (this.isVisitorSuffixFormat(bonid)) {
      this.setOutput("Looking up tourist...", "info");
    } else {
      this.setOutput("Looking up ID…", "info");
    }
    this.showSpinner();
    this.submitButtonTarget.disabled = true;

    const formData = new FormData();
    formData.append("bonid_lookup[bonid]", bonid);
    // Don't send timestamp/signature for manual lookups - this tells the server it's a manual entry
    // formData.append("bonid_lookup[timestamp]", "");
    // formData.append("bonid_lookup[signature]", "");
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
    if (csrfToken) {
      formData.append("bonid_lookup[authenticity_token]", csrfToken);
    } else {
      console.error("CSRF token missing");
      this.setOutput("Submission failed: CSRF token missing.", "danger");
      this.hideSpinner();
      this.submitButtonTarget.disabled = false;
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
        console.log("Received Turbo Stream response:", html);
        if (html.includes("turbo-stream")) {
          // Let Turbo handle the stream response
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
      });
  }

  // Handle confirmation button clicks (Confirm Identity / Not a Match)
  confirmIdentity(event) {
    event.preventDefault();
    const button = event.currentTarget;
    const url = button.dataset.confirmUrl;
    const confirmed = button.dataset.confirmed;

    if (!url) {
      console.error("Missing confirm URL");
      this.setOutput("Confirmation failed: missing URL", "danger");
      return;
    }

    // Show loading state
    const originalHtml = button.innerHTML;
    button.disabled = true;
    button.innerHTML = '<i class="ri-loader-4-line" style="animation: spin 1s linear infinite;"></i> Processing...';

    const formData = new FormData();
    formData.append("confirmed", confirmed);
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
    if (csrfToken) {
      formData.append("authenticity_token", csrfToken);
    }

    fetch(url, {
      method: "POST",
      headers: { Accept: "text/vnd.turbo-stream.html" },
      body: formData
    })
      .then(resp => {
        if (!resp.ok) {
          return resp.text().then(errorText => {
            throw new Error(`Server error: ${resp.status}`);
          });
        }
        return resp.text();
      })
      .then(html => {
        console.log("Confirmation response received");
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

  cancel(event) {
    console.log("Cancel button clicked");
    event.preventDefault();
    if (this.modalEl) {
      const modalInstance = bootstrap.Modal.getInstance(this.modalEl) || bootstrap.Modal.getOrCreateInstance(this.modalEl);
      modalInstance.hide();
      this.reset();
    } else {
      // Not in modal - redirect to officer dashboard
      window.location.href = "/officers/dashboard";
    }
  }

  rescan() {
    console.log("Rescan initiated");
    if (this.modalEl) {
      // In modal - reset and show scanner
      this.reset();
      this.showScannerSection();
      this.initializeScanner();
    } else {
      // Not in modal - refresh the scan page for fresh start
      window.location.href = "/officers/scan";
    }
  }

  reset() {
    console.log("Resetting QR scanner");
    this.stopCamera();
    this.wasScanned = false;
    this.cameras = [];
    this.lastError = null;
    this.clearOutput();
    this.hideSpinner();

    if (this.hasRescanWrapperTarget) this.rescanWrapperTarget.classList.add("d-none");
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
    // Show toggle header again when resetting (for modal context)
    if (this.hasToggleHeaderTarget) this.toggleHeaderTarget.classList.remove("d-none");

    if (this.hasResultFrameTarget && this.hasScannerSectionTarget && this.hasResultSectionTarget) {
      this.resultFrameTarget.innerHTML = '<div class="text-center text-muted small font-body">Scan result will appear here.</div>';
      this.resultFrameTarget.setAttribute("data-result-type", "");
      this.resultSectionTarget.classList.add("d-none");
      this.scannerSectionTarget.classList.remove("d-none");
    }
  }

  showResult() {
    if (this.hasResultSectionTarget) {
      console.log("Showing result section, hiding scanner, manual sections, and toggle header");
      this.resultSectionTarget.classList.remove("d-none");
      if (this.hasScannerSectionTarget) {
        this.scannerSectionTarget.classList.add("d-none");
      }
      if (this.hasManualSectionTarget) {
        this.manualSectionTarget.classList.add("d-none");
      }
      // Hide the Scan/Manual toggle buttons when showing results
      if (this.hasToggleHeaderTarget) {
        this.toggleHeaderTarget.classList.add("d-none");
      }
      // Hide footer when showing results
      if (this.hasFooterTarget) {
        this.footerTarget.classList.add("d-none");
      }
      this.updateButtonVisibility();
    }
    this.wasScanned = false;
  }

  updateButtonVisibility() {
    const resultType = this.resultFrameTarget?.getAttribute("data-result-type");
    console.log("Updating button visibility, resultType:", resultType);

    if (this.hasRescanWrapperTarget) {
      this.rescanWrapperTarget.classList.toggle("d-none", resultType !== "invalid");
    }

    if (this.hasFooterTarget) {
      this.footerTarget.classList.toggle("d-none", resultType === "valid");
    }
  }

  setOutput(message, status = "info") {
    if (!this.hasOutputTarget) return;
    this.outputTarget.textContent = message;
    this.outputTarget.className = `alert alert-${status} text-center small font-body ${message ? "" : "d-none"}`;
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
      audio.play().catch(() => {
        this.setOutput("Audio playback blocked. Enable sound in your browser.", "warning");
      });
    }
  }

  handleError(errorMsg) {
    // Don't show errors if scanner section is hidden (user is in manual mode or viewing results)
    if (this.hasScannerSectionTarget && this.scannerSectionTarget.classList.contains("d-none")) {
      return;
    }
    // Don't repeat the same error
    if (this.lastError === errorMsg) return;
    this.lastError = errorMsg;
    // Only log to console, don't show UI message for normal scanning errors
    // (these happen constantly when no QR is in frame)
    console.log("QR Scanner:", errorMsg);
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