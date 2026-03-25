import { Controller } from "@hotwired/stimulus"

/*
  Evidence Filmstrip Controller — Haiti-Optimized
  ------------------------------------------------
  Horizontal scrollable thumbnail strip for evidence photos/videos.

  Optimizations for Haiti (2G/3G, budget Android):
  1. Client-side image compression — re-encodes uploaded images to ≤1280px, WebP/JPEG
  2. 5MB max per file (down from 10MB) — realistic for 2G upload
  3. Memory cleanup — revokes object URLs, clears pendingFiles after sync
  4. OffscreenCanvas compression — non-blocking on budget Android
  5. Network-adaptive quality — matches camera controller's quality levels
*/

export default class extends Controller {
  static targets = [
    "strip",
    "template",
    "counter",
    "fileInput",
    "removeContainer"
  ]

  static values = {
    maxFiles: { type: Number, default: 10 },
    existingMedia: { type: Array, default: [] }
  }

  connect() {
    // Map of fileId -> { file, objectUrl, source } for new (pending) uploads
    this.pendingFiles = new Map()
    // Set of blob IDs marked for removal on edit
    this.removedBlobIds = new Set()
    // Count of existing files still retained
    this.existingCount = 0

    // Detect WebP + OffscreenCanvas support (same as camera controller)
    this.supportsWebP = this._checkWebPSupport()
    this.mimeType = this.supportsWebP ? "image/webp" : "image/jpeg"
    this.useOffscreen = typeof OffscreenCanvas !== "undefined"

    // Adaptive quality from network
    this.compressQuality = 0.65
    this._detectNetworkQuality()

    // Render existing media thumbnails (edit form)
    if (this.existingMediaValue.length > 0) {
      this.existingMediaValue.forEach(media => {
        this._renderExistingThumb(media)
        this.existingCount++
      })
    }

    // Listen for camera-captured file events
    this._fileAddedHandler = this._onCameraFileAdded.bind(this)
    this.element.addEventListener("evidence-camera:file-added", this._fileAddedHandler)

    // Listen for form submit to sync files
    this.form = this.element.closest("form")
    if (this.form) {
      this._submitHandler = this.syncFiles.bind(this)
      this.form.addEventListener("submit", this._submitHandler)
    }

    this._updateCounter()
  }

  disconnect() {
    this.element.removeEventListener("evidence-camera:file-added", this._fileAddedHandler)

    if (this.form && this._submitHandler) {
      this.form.removeEventListener("submit", this._submitHandler)
    }

    // Revoke all object URLs to prevent memory leaks
    this.pendingFiles.forEach((entry) => {
      if (entry.objectUrl) URL.revokeObjectURL(entry.objectUrl)
    })
    this.pendingFiles.clear()
  }

  // ── Public Actions ──

  // Handle file input change (from "Upload Files" button)
  filesSelected(event) {
    const files = Array.from(event.target.files || [])

    files.forEach(file => {
      // Validate type
      if (!file.type.startsWith("image/") && !file.type.startsWith("video/")) {
        return
      }

      // Validate size — 5MB max for Haiti 2G (down from 10MB)
      if (file.size > 5 * 1024 * 1024) {
        alert(file.name + " exceeds 5MB limit.")
        return
      }

      // Check max files
      if (this._totalCount() >= this.maxFilesValue) {
        alert("Maximum " + this.maxFilesValue + " files reached.")
        return
      }

      const fileId = "upload_" + Date.now() + "_" + Math.random().toString(36).slice(2, 8)

      // Compress images client-side before adding to pending
      if (file.type.startsWith("image/")) {
        this._compressImage(file, fileId)
      } else {
        // Videos pass through as-is
        const objectUrl = URL.createObjectURL(file)
        this.pendingFiles.set(fileId, { file, objectUrl, source: "upload" })
        this._renderNewThumb(fileId, file, objectUrl)
        this._updateCounter()
        this._broadcastFileCount()
      }
    })

    // Clear the input so the same files can be re-selected
    event.target.value = ""
  }

  // Remove a pending (new) file
  removeFile(event) {
    const thumb = event.target.closest("[data-file-id]")
    if (!thumb) return

    const fileId = thumb.dataset.fileId

    if (fileId.startsWith("existing_")) {
      // Existing file on edit — mark for removal
      const blobId = thumb.dataset.blobId
      if (blobId) {
        this.removedBlobIds.add(blobId)
        this._addRemoveInput(blobId)
        thumb.classList.add("evidence-thumb--removed")
        this.existingCount--
      }
    } else {
      // New file — remove entirely
      const entry = this.pendingFiles.get(fileId)
      if (entry && entry.objectUrl) {
        URL.revokeObjectURL(entry.objectUrl)
      }
      this.pendingFiles.delete(fileId)

      // Also notify camera controller if this was a camera capture
      if (fileId.startsWith("cam_")) {
        const cameraCtrl = this.application.getControllerForElementAndIdentifier(
          this.element, "evidence-camera"
        )
        if (cameraCtrl) cameraCtrl.removeCapturedFile(fileId)
      }

      thumb.remove()
    }

    this._updateCounter()
    this._broadcastFileCount()
  }

  // Restore a removed existing file
  restoreFile(event) {
    const thumb = event.target.closest("[data-file-id]")
    if (!thumb) return

    const blobId = thumb.dataset.blobId
    if (blobId) {
      this.removedBlobIds.delete(blobId)
      this._removeRemoveInput(blobId)
      thumb.classList.remove("evidence-thumb--removed")
      this.existingCount++
    }

    this._updateCounter()
    this._broadcastFileCount()
  }

  // Sync all pending files to the file input before form submission
  syncFiles(event) {
    const allFiles = []

    this.pendingFiles.forEach(entry => {
      allFiles.push(entry.file)
    })

    if (allFiles.length === 0) return

    try {
      const dt = new DataTransfer()
      allFiles.forEach(f => dt.items.add(f))
      this.fileInputTarget.files = dt.files
    } catch (err) {
      console.error("Failed to sync files to input:", err)
    }

    // Free memory — files now held by DataTransfer
    this.pendingFiles.forEach(entry => {
      if (entry.objectUrl) URL.revokeObjectURL(entry.objectUrl)
    })
    this.pendingFiles.clear()
  }

  // ── Private: Client-Side Image Compression ──

  // Compress uploaded images to ≤1280px and re-encode as WebP/JPEG
  // Uses OffscreenCanvas if available (non-blocking on budget Android)
  _compressImage(file, fileId) {
    const img = new Image()
    const objectUrl = URL.createObjectURL(file)

    img.onload = () => {
      const maxDim = 1280
      let w = img.naturalWidth
      let h = img.naturalHeight

      // Only compress if image is larger than target
      if (w <= maxDim && h <= maxDim && file.size <= 200 * 1024) {
        // Small enough already — skip compression
        this.pendingFiles.set(fileId, { file, objectUrl, source: "upload" })
        this._renderNewThumb(fileId, file, objectUrl)
        this._updateCounter()
        this._broadcastFileCount()
        return
      }

      // Downscale
      if (w > maxDim || h > maxDim) {
        const scale = maxDim / Math.max(w, h)
        w = Math.floor(w * scale)
        h = Math.floor(h * scale)
      }

      const doCompress = (canvas, ctx) => {
        ctx.drawImage(img, 0, 0, w, h)

        const blobCallback = (blob) => {
          if (!blob) {
            // Compression failed — use original
            this.pendingFiles.set(fileId, { file, objectUrl, source: "upload" })
            this._renderNewThumb(fileId, file, objectUrl)
            this._updateCounter()
            this._broadcastFileCount()
            return
          }

          // Build compressed File
          const ext = this.supportsWebP ? "webp" : "jpg"
          const compressedFile = new File(
            [blob],
            file.name.replace(/\.[^.]+$/, "." + ext),
            { type: this.mimeType, lastModified: Date.now() }
          )

          // Use compressed if smaller, otherwise keep original
          const finalFile = compressedFile.size < file.size ? compressedFile : file
          const finalUrl = URL.createObjectURL(finalFile)

          // Revoke the original objectUrl since we have a new one
          URL.revokeObjectURL(objectUrl)

          this.pendingFiles.set(fileId, { file: finalFile, objectUrl: finalUrl, source: "upload" })
          this._renderNewThumb(fileId, finalFile, finalUrl)
          this._updateCounter()
          this._broadcastFileCount()

          const saved = file.size - finalFile.size
          if (saved > 0) {
            console.info("[Filmstrip] Compressed " + file.name + ": " + (file.size / 1024).toFixed(0) + "KB → " + (finalFile.size / 1024).toFixed(0) + "KB (-" + (saved / 1024).toFixed(0) + "KB)")
          }
        }

        // Use OffscreenCanvas.convertToBlob if available (non-blocking)
        if (canvas instanceof OffscreenCanvas) {
          canvas.convertToBlob({ type: this.mimeType, quality: this.compressQuality })
            .then(blobCallback)
            .catch(() => {
              // Fallback — use original
              this.pendingFiles.set(fileId, { file, objectUrl, source: "upload" })
              this._renderNewThumb(fileId, file, objectUrl)
              this._updateCounter()
              this._broadcastFileCount()
            })
        } else {
          canvas.toBlob(blobCallback, this.mimeType, this.compressQuality)
        }
      }

      // Prefer OffscreenCanvas (off main thread on budget Android)
      if (this.useOffscreen) {
        const offscreen = new OffscreenCanvas(w, h)
        const ctx = offscreen.getContext("2d")
        doCompress(offscreen, ctx)
      } else {
        const canvas = document.createElement("canvas")
        canvas.width = w
        canvas.height = h
        const ctx = canvas.getContext("2d")
        doCompress(canvas, ctx)
      }
    }

    img.onerror = () => {
      // Can't decode image — use original
      this.pendingFiles.set(fileId, { file, objectUrl, source: "upload" })
      this._renderNewThumb(fileId, file, objectUrl)
      this._updateCounter()
      this._broadcastFileCount()
    }

    img.src = objectUrl
  }

  // ── Private: Event Handlers ──

  _onCameraFileAdded(event) {
    const { id, file } = event.detail
    const objectUrl = URL.createObjectURL(file)

    // Camera files are already compressed by the camera controller — no re-compression
    this.pendingFiles.set(id, { file, objectUrl, source: "camera" })
    this._renderNewThumb(id, file, objectUrl)
    this._updateCounter()
    this._broadcastFileCount()
  }

  // ── Private: Rendering ──

  _renderNewThumb(fileId, file, objectUrl) {
    if (!this.hasTemplateTarget || !this.hasStripTarget) return

    const clone = this.templateTarget.content.cloneNode(true)
    const wrapper = clone.querySelector(".evidence-thumb")

    if (wrapper) {
      wrapper.dataset.fileId = fileId

      const img = wrapper.querySelector(".evidence-thumb__img")
      const videoIcon = wrapper.querySelector(".evidence-thumb__video-icon")

      if (file.type.startsWith("video/")) {
        // Show video icon instead of image
        if (img) img.classList.add("d-none")
        if (videoIcon) videoIcon.classList.remove("d-none")
      } else {
        // Show image preview
        if (img) {
          img.src = objectUrl
          img.alt = file.name
        }
        if (videoIcon) videoIcon.classList.add("d-none")
      }

      const nameEl = wrapper.querySelector(".evidence-thumb__name")
      if (nameEl) nameEl.textContent = this._truncate(file.name, 12)

      const sizeEl = wrapper.querySelector(".evidence-thumb__size")
      if (sizeEl) sizeEl.textContent = this._formatSize(file.size)
    }

    this.stripTarget.appendChild(clone)

    // Scroll filmstrip to the end to show new photo
    this.stripTarget.scrollLeft = this.stripTarget.scrollWidth
  }

  _renderExistingThumb(media) {
    if (!this.hasStripTarget) return

    const div = document.createElement("div")
    div.className = "evidence-thumb evidence-thumb--existing"
    div.dataset.fileId = "existing_" + media.id
    div.dataset.blobId = media.id

    const isVideo = (media.contentType || "").startsWith("video/")

    div.innerHTML =
      '<div class="evidence-thumb__img-wrap">' +
        (isVideo
          ? '<div class="evidence-thumb__video-icon"><i class="ri-video-line"></i></div>'
          : '<img src="' + media.url + '" alt="' + (media.filename || "") + '" class="evidence-thumb__img" loading="lazy">') +
        '<button type="button" class="evidence-thumb__remove" data-action="evidence-filmstrip#removeFile">' +
          '<i class="ri-close-line"></i>' +
        '</button>' +
      '</div>' +
      '<div class="evidence-thumb__info">' +
        '<span class="evidence-thumb__name">' + this._truncate(media.filename || "File", 12) + '</span>' +
      '</div>'

    this.stripTarget.appendChild(div)
  }

  // ── Private: Hidden Inputs for Removal ──

  _addRemoveInput(blobId) {
    if (!this.hasRemoveContainerTarget) return
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = "incident_report[remove_media_ids][]"
    input.value = blobId
    input.dataset.blobId = blobId
    this.removeContainerTarget.appendChild(input)
  }

  _removeRemoveInput(blobId) {
    if (!this.hasRemoveContainerTarget) return
    const input = this.removeContainerTarget.querySelector('input[data-blob-id="' + blobId + '"]')
    if (input) input.remove()
  }

  // ── Private: Network + Format Detection ──

  _checkWebPSupport() {
    try {
      const c = document.createElement("canvas")
      c.width = 1
      c.height = 1
      return c.toDataURL("image/webp").indexOf("data:image/webp") === 0
    } catch (e) {
      return false
    }
  }

  _detectNetworkQuality() {
    const conn = navigator.connection || navigator.mozConnection || navigator.webkitConnection
    if (!conn) {
      this.compressQuality = 0.65
      return
    }

    const etype = conn.effectiveType || ""
    switch (etype) {
      case "slow-2g":
      case "2g":
        this.compressQuality = 0.50
        break
      case "3g":
        this.compressQuality = 0.60
        break
      case "4g":
        this.compressQuality = 0.75
        break
      default:
        this.compressQuality = 0.65
    }
  }

  // ── Private: Counters & Utilities ──

  _totalCount() {
    return this.pendingFiles.size + this.existingCount
  }

  _updateCounter() {
    if (!this.hasCounterTarget) return
    const total = this._totalCount()
    this.counterTarget.textContent = total + " / " + this.maxFilesValue + " files"

    if (total >= this.maxFilesValue) {
      this.counterTarget.style.color = "var(--law-red)"
    } else if (total >= this.maxFilesValue - 2) {
      this.counterTarget.style.color = "#E5A100"
    } else {
      this.counterTarget.style.color = ""
    }
  }

  _broadcastFileCount() {
    // Share count with camera controller via dataset
    this.element.dataset.evidenceFilmstripFileCount = this.pendingFiles.size + this.existingCount
  }

  _truncate(str, len) {
    if (!str) return ""
    return str.length > len ? str.slice(0, len - 1) + "\u2026" : str
  }

  _formatSize(bytes) {
    if (bytes < 1024) return bytes + " B"
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(0) + " KB"
    return (bytes / (1024 * 1024)).toFixed(1) + " MB"
  }
}
