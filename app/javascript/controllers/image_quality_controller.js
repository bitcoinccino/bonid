import { Controller } from "@hotwired/stimulus"

// In-browser ID-photo quality gate. Runs after the citizen captures a
// document photo (before the file is accepted by the form) so blurry or
// flash-glare photos get caught immediately instead of failing later in
// the AWS Rekognition pipeline. Checks:
//
//   1. Blur — Laplacian variance < blurThresholdValue → "Foto a flou…"
//   2. Glare — clipped-white pixel % > glareMaxPctValue → "Pa sèvi ak flach…"
//
// On failure the controller clears the file input so the wizard's existing
// `required` validation still blocks Continue. On pass it shows a green
// confirmation under the field. Coverage / edge detection is intentionally
// left out of v1 — too easy to false-positive on light documents.
//
// Usage:
//   <div data-controller="image-quality">
//     <input type="file" data-image-quality-target="input" ...>
//     <div data-image-quality-target="status" class="small mt-1"></div>
//   </div>
export default class extends Controller {
  static targets = ["input", "status", "thumbnail"]
  static values = {
    blurThreshold:  { type: Number, default: 60 },
    glareMaxPct:    { type: Number, default: 15 },
    glareLuminance: { type: Number, default: 245 },
    sampleWidth:    { type: Number, default: 600 }, // resize for fast analysis
    maxFileSize:    { type: Number, default: 5 * 1024 * 1024 } // 5 MB — AWS Rekognition cap
  }

  connect() {
    if (!this.hasInputTarget) return
    this._handler = this.onFileSelected.bind(this)
    this.inputTarget.addEventListener("change", this._handler)
  }

  disconnect() {
    if (this.hasInputTarget && this._handler) {
      this.inputTarget.removeEventListener("change", this._handler)
    }
  }

  async onFileSelected(event) {
    const file = event.target.files && event.target.files[0]
    if (!file) {
      this.clearStatus()
      this.clearThumbnail()
      return
    }

    // Skip the gate for non-image files (PDFs etc) — those bypass canvas.
    if (!file.type.startsWith("image/")) {
      this.showStatus("warning", "Aksepte. Foto pa tcheke pou kalite.")
      this.clearThumbnail()
      return
    }

    // Hard size cap — AWS Rekognition rejects >5MB. Catch it here so the
    // citizen doesn't burn a network round-trip on a doomed upload.
    if (file.size > this.maxFileSizeValue) {
      event.target.value = ""
      this.clearThumbnail()
      const sizeMb = (file.size / 1024 / 1024).toFixed(1)
      this.showStatus("failed",
        `Foto twò gwo (${sizeMb} MB). Limit la se 5 MB. Pran yon foto pi piti oswa konprese li.`)
      return
    }

    this.showStatus("checking", "Ap tcheke kalite foto a…")

    try {
      const img = await this._fileToImage(file)
      const canvas = this._toCanvas(img, this.sampleWidthValue)
      const data = canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height)
      const issues = []

      if (this._isBlurry(data)) {
        issues.push("Foto a flou. Kenbe telefòn ou estab epi eseye ankò.")
      }
      if (this._hasGlare(data)) {
        issues.push("Genyen reflè flach. Pa sèvi ak flach, eseye nan limyè natirèl.")
      }

      if (issues.length > 0) {
        // Clear the file so the wizard's required-field check blocks Continue.
        event.target.value = ""
        this.clearThumbnail()
        this.showStatus("failed", issues.join(" "))
      } else {
        this.showStatus("passed", "Foto a klè ✓")
        // Reuse the analysis canvas for the thumbnail — no second decode.
        this._renderThumbnail(canvas.toDataURL("image/jpeg", 0.75))
      }
    } catch (err) {
      console.warn("[image-quality] check failed, accepting file:", err)
      this.showStatus("warning", "Aksepte. Pa kapab tcheke kalite a otomatikman.")
      // Fall back to the raw file for the thumbnail so the citizen still
      // sees what they uploaded even when our canvas analysis crashes.
      this._renderThumbnailFromFile(file)
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────

  _fileToImage(file) {
    return new Promise((resolve, reject) => {
      const url = URL.createObjectURL(file)
      const img = new Image()
      img.onload  = () => { URL.revokeObjectURL(url); resolve(img) }
      img.onerror = (e) => { URL.revokeObjectURL(url); reject(e) }
      img.src = url
    })
  }

  // Downscale to a fixed width before analysis so the math stays cheap on
  // mid-tier Android phones. ImageData of a 600px-wide canvas is ~1MB.
  // Returns the canvas itself so the caller can both extract ImageData
  // for analysis AND a DataURL for the thumbnail without a second decode.
  _toCanvas(img, maxWidth) {
    const w = Math.min(img.width, maxWidth)
    const h = Math.round(w * (img.height / img.width))
    const canvas = document.createElement("canvas")
    canvas.width = w
    canvas.height = h
    canvas.getContext("2d").drawImage(img, 0, 0, w, h)
    return canvas
  }

  // Laplacian variance: grayscale → 3×3 Laplacian → variance. Low variance
  // means little high-frequency content → blurry. The threshold is empirical;
  // ~60 catches obvious blur without false-positiving clean phone shots.
  _isBlurry(imageData) {
    const { data, width, height } = imageData
    const gray = new Float32Array(width * height)
    for (let i = 0; i < data.length; i += 4) {
      gray[i >> 2] = 0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2]
    }

    let sum = 0, sumSq = 0, count = 0
    for (let y = 1; y < height - 1; y++) {
      for (let x = 1; x < width - 1; x++) {
        const i = y * width + x
        const lap = 4 * gray[i] - gray[i - 1] - gray[i + 1] - gray[i - width] - gray[i + width]
        sum   += lap
        sumSq += lap * lap
        count += 1
      }
    }
    const mean = sum / count
    const variance = (sumSq / count) - (mean * mean)
    return variance < this.blurThresholdValue
  }

  // Glare: % of pixels with R+G+B above the clipping threshold. >15% = flash
  // burned out a chunk of the document, which Rekognition will fail to OCR.
  _hasGlare(imageData) {
    const { data } = imageData
    const total = data.length / 4
    const threshold = this.glareLuminanceValue * 3
    let clipped = 0
    for (let i = 0; i < data.length; i += 4) {
      if (data[i] + data[i + 1] + data[i + 2] > threshold) clipped += 1
    }
    return (clipped / total) * 100 > this.glareMaxPctValue
  }

  showStatus(state, message) {
    if (!this.hasStatusTarget) return
    const t = this.statusTarget
    t.dataset.state = state
    t.textContent = message
    const colorClass =
      state === "passed"   ? "text-success" :
      state === "failed"   ? "text-danger"  :
      state === "warning"  ? "text-warning" :
      state === "checking" ? "text-muted"   :
                             "text-muted"
    t.className = `image-quality-status mt-1 small d-block ${colorClass}`
  }

  clearStatus() {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = ""
    this.statusTarget.dataset.state = ""
  }

  // Renders a thumbnail of the captured photo so the citizen can confirm
  // they uploaded the right side of the document before tapping Continue.
  // Replaces the generic "✓ Uploaded" text with an actual image preview.
  _renderThumbnail(dataUrl) {
    if (!this.hasThumbnailTarget) return
    this.thumbnailTarget.innerHTML = `
      <div class="d-flex align-items-center gap-2 mt-2 p-2 rounded-3"
           style="background: #F8FAFC; border: 1px solid #E5E7EB;">
        <img src="${dataUrl}" alt="Preview"
             style="width: 56px; height: 56px; object-fit: cover; border-radius: 6px; flex-shrink: 0;">
        <div class="small text-muted" style="font-size: 0.75rem;">
          Foto seleksyone. Tcheke ke se bon bò dokiman an.
        </div>
      </div>
    `
  }

  _renderThumbnailFromFile(file) {
    if (!this.hasThumbnailTarget) return
    const reader = new FileReader()
    reader.onload = () => this._renderThumbnail(reader.result)
    reader.readAsDataURL(file)
  }

  clearThumbnail() {
    if (this.hasThumbnailTarget) this.thumbnailTarget.innerHTML = ""
  }
}
