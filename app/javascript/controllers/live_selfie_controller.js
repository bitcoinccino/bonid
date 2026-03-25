import { Controller } from "@hotwired/stimulus"

/*
  Live Selfie Controller — Final Production Version
  ------------------------------------------------
  ✔ Front-facing camera only
  ✔ Guided liveness instruction
  ✔ High-quality capture
  ✔ Preview + Retake + Confirm flow
  ✔ Seamless ActiveStorage integration
  ✔ Mobile-optimized
*/

export default class extends Controller {
  static targets = [
    "video",
    "canvas",
    "preview",
    "file",
    "instruction",
    "captureBtn",
    "retakeBtn",
    "confirmBtn"
  ]

  connect() {
    this.stream = null
    this.captureEnabled = false

    // Check if nested inside a wizard step (citizen submission form)
    this.stepSection = this.element.closest("[data-wizard-target='step']")

    if (this.stepSection) {
      // Lazy-start: observe the parent step section for visibility changes
      this._observer = new MutationObserver(() => {
        const isVisible = !this.stepSection.classList.contains("d-none")
        if (isVisible && !this.stream) {
          this.startCamera()
        } else if (!isVisible && this.stream) {
          this.stopCamera()
        }
      })
      this._observer.observe(this.stepSection, { attributes: true, attributeFilter: ["class"] })

      // Also start immediately if the step is already visible (e.g. page refresh on this step)
      if (!this.stepSection.classList.contains("d-none")) {
        this.startCamera()
      }
    } else {
      // Auto-start: standalone form (e.g. BonTouris documents page)
      this.startCamera()
    }
  }

  async startCamera() {
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: "user",
          width: { ideal: 1280 },
          height: { ideal: 720 }
        },
        audio: false
      })

      this.videoTarget.srcObject = this.stream
      await this.videoTarget.play()

      // Hide preview, show live video
      this.previewTarget.classList.add("d-none")
      this.videoTarget.classList.remove("d-none")

      this.updateInstruction("Turn your head slightly LEFT, then tap Capture")

      // Brief delay to let user settle
      this.disableCapture()
      setTimeout(() => this.enableCapture(), 1500)

    } catch (error) {
      console.error("Camera access failed:", error)
      this.updateInstruction("Camera access denied or unavailable")
      alert("Camera access is required to take a live selfie.")
    }
  }

  stopCamera() {
    if (this.stream) {
      this.stream.getTracks().forEach(track => track.stop())
      this.stream = null
    }
  }

  updateInstruction(text) {
    if (this.hasInstructionTarget) {
      this.instructionTarget.textContent = text
    }
  }

  enableCapture() {
    this.captureEnabled = true
    this.captureBtnTarget.disabled = false
    this.captureBtnTarget.classList.remove("disabled")
  }

  disableCapture() {
    this.captureEnabled = false
    this.captureBtnTarget.disabled = true
    this.captureBtnTarget.classList.add("disabled")
  }

  capture() {
    if (!this.captureEnabled) return

    const video = this.videoTarget
    const canvas = this.canvasTarget
    const ctx = canvas.getContext("2d")

    // Match canvas to actual video dimensions
    canvas.width = video.videoWidth
    canvas.height = video.videoHeight
    ctx.drawImage(video, 0, 0)

    canvas.toBlob(blob => {
      if (!blob) {
        alert("Capture failed. Please try again.")
        return
      }

      const file = new File([blob], "live_selfie.jpg", {
        type: "image/jpeg",
        lastModified: Date.now()
      })

      const dt = new DataTransfer()
      dt.items.add(file)
      this.fileTarget.files = dt.files

      // Show preview
      const previewUrl = URL.createObjectURL(blob)
      this.previewTarget.src = previewUrl
      this.previewTarget.classList.remove("d-none")
      this.videoTarget.classList.add("d-none")

      // Switch UI state
      this.stopCamera()
      this.captureBtnTarget.classList.add("d-none")
      this.retakeBtnTarget.classList.remove("d-none")
      this.confirmBtnTarget.classList.remove("d-none")

      this.updateInstruction("Review your photo and confirm")
    }, "image/jpeg", 0.92) // High quality, smaller than 0.95
  }

  // Used in citizen wizard where confirm doesn't submit the form
  confirm() {
    this.confirmBtnTarget.classList.add("d-none")
    this.retakeBtnTarget.classList.remove("d-none")
    this.updateInstruction("✓ Selfie confirmed — proceed to next step")
    this.previewTarget.style.borderColor = "#198754" // success green
  }

  retake() {
    // Clear file input
    this.fileTarget.value = ""

    // Reset preview/video
    this.previewTarget.classList.add("d-none")
    this.videoTarget.classList.remove("d-none")

    // Reset buttons
    this.retakeBtnTarget.classList.add("d-none")
    this.confirmBtnTarget.classList.add("d-none")
    this.captureBtnTarget.classList.remove("d-none")

    this.updateInstruction("Turn your head slightly LEFT, then tap Capture")
    this.startCamera()
  }

  disconnect() {
    this.stopCamera()
    if (this._observer) {
      this._observer.disconnect()
      this._observer = null
    }
  }
}