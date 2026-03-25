import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="signature-pad"
export default class extends Controller {
  static targets = [
    "canvas",
    "previewWrapper",
    "previewImage",
    "submitButton",
    "fileInput"
  ]

  connect() {
    this.canvas = this.canvasTarget
    this.ctx = this.canvas.getContext("2d")
    this.isDrawing = false

    this.resizeCanvas()
    this.bindEvents()
    this.toggleSubmitButton(false)

    // ✅ Run a second resize after layout stabilizes
    requestAnimationFrame(() => this.resizeCanvas())

    console.log("✅ SignaturePad connected and ready")

    // ✅ Optional: re-scale when window resizes
    this.handleResize = () => this.resizeCanvas()
    window.addEventListener("resize", this.handleResize)
  }

  disconnect() {
    window.removeEventListener("resize", this.handleResize)
  }

  // ---- Drawing Logic ----
  bindEvents() {
    // Mouse
    this.canvas.addEventListener("mousedown", e => this.startDrawing(e))
    this.canvas.addEventListener("mousemove", e => this.draw(e))
    this.canvas.addEventListener("mouseup", () => this.stopDrawing())
    this.canvas.addEventListener("mouseout", () => this.stopDrawing())

    // Touch
    this.canvas.addEventListener("touchstart", e => this.startDrawing(e), { passive: false })
    this.canvas.addEventListener("touchmove", e => this.draw(e), { passive: false })
    this.canvas.addEventListener("touchend", () => this.stopDrawing())

    // File upload fallback
    if (this.hasFileInputTarget) {
      this.fileInputTarget.addEventListener("change", () => {
        this.toggleSubmitButton(this.fileInputTarget.files.length > 0)
      })
    }
  }

  startDrawing(event) {
    event.preventDefault()
    const { x, y } = this.getXY(event)
    this.isDrawing = true
    this.ctx.beginPath()
    this.ctx.moveTo(x, y)
  }

  draw(event) {
    if (!this.isDrawing) return
    event.preventDefault()
    const { x, y } = this.getXY(event)
    this.ctx.lineTo(x, y)
    this.ctx.stroke()
    this.updatePreview()
  }

  stopDrawing() {
    if (!this.isDrawing) return
    this.isDrawing = false
    this.updatePreview()
  }

  clear() {
    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height)
    if (this.hasPreviewWrapperTarget) this.previewWrapperTarget.style.display = "none"
    this.toggleSubmitButton(false)
  }

  resizeCanvas() {
    const ratio = window.devicePixelRatio || 1
    const width = this.canvas.offsetWidth || 400
    const height = this.canvas.offsetHeight || 150

    this.canvas.width = width * ratio
    this.canvas.height = height * ratio
    this.ctx.setTransform(ratio, 0, 0, ratio, 0, 0) // ✅ safer scaling

    this.ctx.lineWidth = 2
    this.ctx.lineCap = "round"
    this.ctx.lineJoin = "round"
    this.ctx.strokeStyle = "#000"
  }

  getXY(event) {
    const rect = this.canvas.getBoundingClientRect()
    const clientX = event.touches ? event.touches[0].clientX : event.clientX
    const clientY = event.touches ? event.touches[0].clientY : event.clientY
    return { x: clientX - rect.left, y: clientY - rect.top }
  }

  updatePreview() {
    const dataURL = this.canvas.toDataURL("image/png", 0.85)

    // Update optional preview
    if (this.hasPreviewImageTarget && this.hasPreviewWrapperTarget) {
      this.previewImageTarget.src = dataURL
      this.previewWrapperTarget.style.display = "block"
    }

    // Automatically fill hidden file input for Rails ActiveStorage
    if (this.hasFileInputTarget) {
      fetch(dataURL)
        .then(res => res.blob())
        .then(blob => {
          const file = new File([blob], "signature.png", { type: "image/png" })
          const dataTransfer = new DataTransfer()
          dataTransfer.items.add(file)
          this.fileInputTarget.files = dataTransfer.files
          this.toggleSubmitButton(true)
        })
    } else {
      this.toggleSubmitButton(true)
    }
  }

  toggleSubmitButton(enabled = false) {
    if (!this.hasSubmitButtonTarget) return
    this.submitButtonTarget.disabled = !enabled
    this.submitButtonTarget.classList.toggle("opacity-50", !enabled)
    this.submitButtonTarget.classList.toggle("cursor-not-allowed", !enabled)
  }
}
