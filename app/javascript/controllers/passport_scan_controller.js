import { Controller } from "@hotwired/stimulus"

// Passport Scanner — Camera capture + OCR auto-fill via AWS Textract.
//
// Opens the rear camera, captures a frame, POSTs it to the scan endpoint,
// and auto-fills form fields with the extracted passport data.
// The captured image is also stored for face comparison in the liveness flow.
export default class extends Controller {
  static targets = [
    "cameraContainer",
    "video",
    "canvas",
    "scanButton",
    "statusMessage",
    "passportPhotoInput",
    // Form field targets for auto-fill
    "firstName",
    "lastName",
    "dob",
    "sex",
    "nationality",
    "passportNumber",
    "passportExpiryDate"
  ]

  static values = {
    scanUrl: { type: String, default: "/public/visitors/scan_passport" }
  }

  connect() {
    this._stream = null
    this._scanning = false
  }

  disconnect() {
    this.closeCamera()
  }

  // ── Camera ──

  async openCamera() {
    if (this._stream) return

    if (this.hasCameraContainerTarget) {
      this.cameraContainerTarget.classList.remove("d-none")
    }

    try {
      this._stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: { ideal: "environment" },
          width: { ideal: 1280 },
          height: { ideal: 720 }
        },
        audio: false
      })

      if (this.hasVideoTarget) {
        this.videoTarget.srcObject = this._stream
        this.videoTarget.play()
      }

      this._updateStatus("", "")
    } catch (err) {
      console.error("[passport-scan] Camera access denied:", err)
      this._updateStatus("Camera access denied. Please allow camera permissions.", "text-danger")
    }
  }

  closeCamera() {
    if (this._stream) {
      this._stream.getTracks().forEach(track => track.stop())
      this._stream = null
    }

    if (this.hasVideoTarget) {
      this.videoTarget.srcObject = null
    }

    if (this.hasCameraContainerTarget) {
      this.cameraContainerTarget.classList.add("d-none")
    }
  }

  // ── Capture & OCR ──

  async capture() {
    if (this._scanning) return
    if (!this._stream || !this.hasVideoTarget || !this.hasCanvasTarget) return

    this._scanning = true
    this._updateStatus("Scanning passport...", "text-primary")

    try {
      // Draw frame to canvas
      const video = this.videoTarget
      const canvas = this.canvasTarget
      canvas.width = video.videoWidth
      canvas.height = video.videoHeight
      const ctx = canvas.getContext("2d")
      ctx.drawImage(video, 0, 0)

      // Convert to blob
      const blob = await new Promise((resolve) =>
        canvas.toBlob(resolve, "image/jpeg", 0.85)
      )

      if (!blob) {
        this._updateStatus("Failed to capture image.", "text-danger")
        this._scanning = false
        return
      }

      // Store captured image for face comparison
      this._storePassportPhoto(blob)

      // POST to OCR endpoint
      await this._uploadForOcr(blob)
    } catch (err) {
      console.error("[passport-scan] Capture error:", err)
      this._updateStatus("Scan failed. Please try again.", "text-danger")
    } finally {
      this._scanning = false
    }
  }

  async _uploadForOcr(blob) {
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    const formData = new FormData()
    formData.append("passport_image", blob, "passport.jpg")

    try {
      const resp = await fetch(this.scanUrlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": csrfToken },
        body: formData
      })

      if (!resp.ok) {
        const data = await resp.json().catch(() => ({}))
        this._updateStatus(
          data.error || "Could not read passport. Please enter details manually.",
          "text-danger"
        )
        return
      }

      const result = await resp.json()

      if (result.success && result.fields) {
        this._autoFill(result.fields)
        this._playSuccessBeep()
        this._updateStatus("Passport scanned successfully!", "text-success")
        this.closeCamera()
      } else {
        this._updateStatus(
          result.error || "Could not read passport. Please enter details manually.",
          "text-danger"
        )
      }
    } catch (err) {
      console.error("[passport-scan] OCR upload error:", err)
      this._updateStatus("Network error. Please try again.", "text-danger")
    }
  }

  // ── Auto-fill ──

  _autoFill(fields) {
    const mappings = {
      firstName: fields.first_name,
      lastName: fields.last_name,
      dob: fields.dob,
      sex: fields.sex,
      nationality: fields.nationality,
      passportNumber: fields.passport_number,
      passportExpiryDate: fields.passport_expiry_date
    }

    Object.entries(mappings).forEach(([targetName, value]) => {
      if (!value) return
      const hasTarget = `has${targetName.charAt(0).toUpperCase() + targetName.slice(1)}Target`
      if (!this[hasTarget]) return

      const target = this[`${targetName}Target`]
      target.value = value

      // Trigger change event for any dependent controllers
      target.dispatchEvent(new Event("change", { bubbles: true }))
      target.dispatchEvent(new Event("input", { bubbles: true }))

      // Green flash animation
      target.classList.add("ocr-field-flash")
      setTimeout(() => target.classList.remove("ocr-field-flash"), 600)
    })

    // Persist auto-filled values
    this._persistValues(fields)
  }

  // ── Passport Photo Storage ──

  // Stores the captured passport image in a hidden file input
  // so liveness_detector_controller can access it for face comparison.
  _storePassportPhoto(blob) {
    if (!this.hasPassportPhotoInputTarget) return

    const file = new File([blob], "passport_photo.jpg", { type: "image/jpeg" })
    const dataTransfer = new DataTransfer()
    dataTransfer.items.add(file)
    this.passportPhotoInputTarget.files = dataTransfer.files

    // Trigger change so liveness_detector_controller caches it
    this.passportPhotoInputTarget.dispatchEvent(new Event("change", { bubbles: true }))

    console.info("[passport-scan] Stored passport photo for face comparison")
  }

  // ── Persistence ──

  _persistValues(fields) {
    try {
      localStorage.setItem("bonid_passport_ocr", JSON.stringify({
        ...fields,
        timestamp: Date.now()
      }))
    } catch (e) { /* ignore */ }
  }

  // ── UI ──

  _updateStatus(message, cssClass) {
    if (!this.hasStatusMessageTarget) return

    if (!message) {
      this.statusMessageTarget.innerHTML = ""
      return
    }

    this.statusMessageTarget.innerHTML = `
      <p class="small fw-semibold ${cssClass} mb-0 mt-2">
        ${this._escapeHtml(message)}
      </p>
    `
  }

  _escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }

  // ── Audio Feedback ──

  _playSuccessBeep() {
    try {
      const ctx = new (window.AudioContext || window.webkitAudioContext)()
      const osc = ctx.createOscillator()
      const gain = ctx.createGain()

      osc.connect(gain)
      gain.connect(ctx.destination)

      osc.type = "sine"
      osc.frequency.setValueAtTime(880, ctx.currentTime)
      gain.gain.setValueAtTime(0.15, ctx.currentTime)
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.3)

      osc.start(ctx.currentTime)
      osc.stop(ctx.currentTime + 0.3)
    } catch (e) { /* non-fatal */ }
  }
}
