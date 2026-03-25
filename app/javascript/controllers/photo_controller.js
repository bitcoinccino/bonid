import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="photo-preview"
export default class extends Controller {
  static targets = ["input", "preview", "placeholder", "spinner"]

  preview(event) {
    const file = event.target.files[0]
    if (!file) return

    // Validate file type and size (<= 5MB)
    if (!file.type.startsWith("image/")) {
      alert("Please upload a valid image (JPEG or PNG).")
      this.resetInput()
      return
    }
    if (file.size > 5 * 1024 * 1024) {
      alert("Image too large (max 5MB).")
      this.resetInput()
      return
    }

    // Show spinner if present
    if (this.hasSpinnerTarget) this.spinnerTarget.classList.remove("d-none")

    const reader = new FileReader()
    reader.onload = (e) => {
      this.showPreview(e.target.result)
    }
    reader.onerror = () => {
      alert("Failed to load image.")
    }

    reader.readAsDataURL(file)
  }

  showPreview(dataUrl) {
    if (this.hasSpinnerTarget) this.spinnerTarget.classList.add("d-none")

    const img = this.previewTarget.querySelector("img") || document.createElement("img")
    img.src = dataUrl
    img.className = "photo-preview rounded-circle shadow-sm border border-3 border-light"
    img.alt = "Profile photo preview"
    img.style = "width: 180px; height: 180px; object-fit: cover;"

    this.previewTarget.innerHTML = ""
    this.previewTarget.appendChild(img)

    if (this.hasPlaceholderTarget) this.placeholderTarget.classList.add("d-none")
  }

  resetInput() {
    if (this.hasInputTarget) this.inputTarget.value = ""
  }
}
