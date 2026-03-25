import { Controller } from "@hotwired/stimulus"

// Bridges the React FaceLivenessDetector with the Stimulus wizard.
// Mounts/unmounts the React component based on wizard step visibility.
//
// After liveness passes, IMMEDIATELY compares the selfie against the
// uploaded ID photo (CIN front or Passport) via the face_compare endpoint.
// Blocks progression to Step 3 if faces don't match.
export default class extends Controller {
  static targets = [
    "mountPoint",
    "file",
    "statusMessage",
    "retryBtn"
  ]

  static values = {
    passed: { type: Boolean, default: false },
    region: { type: String, default: "us-east-1" },
    identityPoolId: { type: String, default: "" },
    createSessionUrl: { type: String, default: "" },
    resultsUrl: { type: String, default: "" },
    statusUrl: { type: String, default: "" },
    manualSelfieUrl: { type: String, default: "" },
    faceCompareUrl: { type: String, default: "" }
  }

  connect() {
    this.mounted = false
    this._attemptTracker = this._loadAttemptTracker()
    this._cachedIdPhoto = null

    // Register service worker for offline liveness asset caching.
    // On Haiti's mobile networks, this ensures returning users don't
    // re-download the 3.5MB Amplify bundle if their connection drops.
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.register("/liveness-sw.js", { scope: "/" })
        .catch(() => {}) // non-fatal: assets load normally if SW fails
    }

    // Cache ID photo files as soon as they're selected in Step 1.
    // On mobile iOS, hidden file inputs lose their `files` reference
    // when the parent step gets d-none. Caching prevents this.
    this._setupIdPhotoCaching()

    this.stepSection = this.element.closest("[data-wizard-target='step']")
    if (this.stepSection) {
      this._observer = new MutationObserver(() => {
        const isVisible = !this.stepSection.classList.contains("d-none")
        if (isVisible && !this.mounted && !this.passedValue) {
          this.mountLiveness()
        } else if (!isVisible && this.mounted) {
          this.unmountLiveness()
        }
      })
      this._observer.observe(this.stepSection, { attributes: true, attributeFilter: ["class"] })

      if (!this.stepSection.classList.contains("d-none") && !this.passedValue) {
        this.mountLiveness()
      }
    }
  }

  mountLiveness() {
    if (this.mounted || !this.hasMountPointTarget) return
    if (this.passedValue) return

    if (!window.BonidLiveness) {
      console.warn("[liveness-detector] Bundle not loaded yet, retrying...")
      setTimeout(() => this.mountLiveness(), 500)
      return
    }

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    const mountOptions = {
      csrfToken,
      region: this.regionValue,
      identityPoolId: this.identityPoolIdValue,
      attemptTracker: this._attemptTracker,
      onComplete: (data) => this.handleComplete(data),
      onError: (data) => this.handleError(data)
    }

    // Pass URL overrides if configured (visitor flow uses different endpoints)
    if (this.createSessionUrlValue) mountOptions.createSessionUrl = this.createSessionUrlValue
    if (this.resultsUrlValue) mountOptions.resultsUrl = this.resultsUrlValue
    if (this.statusUrlValue) mountOptions.statusUrl = this.statusUrlValue
    if (this.manualSelfieUrlValue) mountOptions.manualSelfieUrl = this.manualSelfieUrlValue

    window.BonidLiveness.mount(this.mountPointTarget, mountOptions)

    this.mounted = true
  }

  unmountLiveness() {
    if (!this.mounted) return
    window.BonidLiveness?.unmount()
    this.mounted = false
  }

  // Called by React on successful liveness pass
  async handleComplete(data) {
    // Clear attempt tracker on success
    this._attemptTracker.attempts = []
    this._saveAttemptTracker()

    // Inject the blob signed_id into the hidden field for form submission
    if (this.hasFileTarget && data.blob_signed_id) {
      this.fileTarget.value = data.blob_signed_id
    }

    // Hide the React mount point
    if (this.hasMountPointTarget) {
      this.mountPointTarget.classList.add("d-none")
    }
    this.unmountLiveness()

    // Show "comparing" state while we check face match
    this._showComparingState()

    // Run face comparison against the uploaded ID photo
    const matchResult = await this._compareFaceWithId(data.blob_signed_id)

    if (matchResult.match) {
      // Face matched — allow progression
      this.passedValue = true
      this._showSuccessState(matchResult.similarity)
      // Clean up cached photo from sessionStorage
      this._clearIdPhotoCache()
      // Hide the Back/Previous buttons on Step 2 — no going back after match
      this._hideStepBackButtons()
    } else if (matchResult.error) {
      // AWS error or network issue — BLOCK. Do NOT silently allow through.
      // The user must retry. FaceMatchJob is a safety net, not a replacement.
      this.passedValue = false
      this._showErrorState()
    } else {
      // Face does NOT match — block progression
      this.passedValue = false
      this._showMismatchState(matchResult.message)
    }
  }

  // Called by React on error — only track attempts, do NOT render error HTML.
  // Error display is handled entirely within the React component.
  handleError(data) {
    this.passedValue = false
    this._attemptTracker.attempts = [...(this._attemptTracker.attempts || []), Date.now()]
    this._saveAttemptTracker()
  }

  retry() {
    this.passedValue = false
    if (this.hasMountPointTarget) {
      this.mountPointTarget.classList.remove("d-none")
      this.mountPointTarget.innerHTML = ""
    }
    if (this.hasStatusMessageTarget) {
      this.statusMessageTarget.innerHTML = ""
    }
    if (this.hasRetryBtnTarget) {
      this.retryBtnTarget.classList.add("d-none")
    }
    this.mountLiveness()
  }

  disconnect() {
    this.unmountLiveness()
    if (this._observer) {
      this._observer.disconnect()
      this._observer = null
    }
  }

  // ── ID Photo Caching (3-Layer: DataURL + File + sessionStorage) ──

  // PROBLEM: On iOS Safari and some mobile browsers, file inputs inside
  // hidden elements (d-none) lose their `files` reference. Since Step 1
  // is hidden when Step 2 (liveness) runs, the face comparison can't find
  // the ID photo, causing it to silently skip — a critical security gap.
  //
  // SOLUTION: 3-layer cache ensures the ID photo is ALWAYS available:
  //   Layer 1: Convert to DataURL and store in sessionStorage (survives DOM changes)
  //   Layer 2: Keep File object reference as fallback
  //   Layer 3: Reconstruct File from sessionStorage DataURL if both above fail
  _setupIdPhotoCaching() {
    const form = this.element.closest("form")
    if (!form) return

    const inputs = [
      form.querySelector("input[name='identity_submission[cin_front]']"),
      form.querySelector("input[name='identity_submission[passport]']")
    ].filter(Boolean)

    inputs.forEach(input => {
      // Cache file on selection — both as File object AND DataURL
      input.addEventListener("change", () => {
        if (input.files?.length > 0) {
          this._cacheIdPhotoFile(input.files[0])
        }
      })
      // Grab existing file if already selected before controller connected
      if (input.files?.length > 0) {
        this._cacheIdPhotoFile(input.files[0])
      }
    })

    // Layer 3: Restore from sessionStorage if no live file found
    // (handles case where controller connects AFTER file was selected and step hidden)
    if (!this._cachedIdPhoto) {
      this._restoreIdPhotoFromStorage()
    }
  }

  // Caches the ID photo as both a File object and a DataURL in sessionStorage
  _cacheIdPhotoFile(file) {
    this._cachedIdPhoto = file
    console.info("[liveness-detector] Cached ID photo (File):", file.name)

    // Convert to DataURL for persistent storage (survives d-none, page state changes)
    const reader = new FileReader()
    reader.onload = () => {
      try {
        sessionStorage.setItem("bonid_id_photo_data", reader.result)
        sessionStorage.setItem("bonid_id_photo_name", file.name)
        sessionStorage.setItem("bonid_id_photo_type", file.type)
        console.info("[liveness-detector] Cached ID photo (DataURL) in sessionStorage")
      } catch (e) {
        // sessionStorage quota exceeded (rare, ~5MB limit) — File cache still works
        console.warn("[liveness-detector] sessionStorage cache failed:", e.message)
      }
    }
    reader.readAsDataURL(file)
  }

  // Restores a File object from sessionStorage DataURL
  _restoreIdPhotoFromStorage() {
    try {
      const dataUrl = sessionStorage.getItem("bonid_id_photo_data")
      const name = sessionStorage.getItem("bonid_id_photo_name")
      const type = sessionStorage.getItem("bonid_id_photo_type")
      if (!dataUrl || !name) return

      // Convert DataURL back to File
      const byteString = atob(dataUrl.split(",")[1])
      const ab = new ArrayBuffer(byteString.length)
      const ia = new Uint8Array(ab)
      for (let i = 0; i < byteString.length; i++) {
        ia[i] = byteString.charCodeAt(i)
      }
      this._cachedIdPhoto = new File([ab], name, { type: type || "image/jpeg" })
      console.info("[liveness-detector] Restored ID photo from sessionStorage:", name)
    } catch (e) {
      console.warn("[liveness-detector] Failed to restore ID photo from sessionStorage:", e.message)
    }
  }

  // ── Face Comparison ──

  async _compareFaceWithId(selfieBlobSignedId) {
    const idPhoto = this._getIdPhotoFile()

    if (!idPhoto) {
      // No ID photo found — block progression (don't silently allow through)
      console.warn("[liveness-detector] No ID photo found in form or cache, blocking")
      return { match: false, message: "Dokiman idantite'w pa anrejistre. Tanpri retounen nan Etap 1 epi telechaje foto idantite ou anvan ou kontinye." }
    }

    try {
      const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
      const formData = new FormData()
      formData.append("selfie_blob_signed_id", selfieBlobSignedId)
      formData.append("id_photo", idPhoto)

      const compareUrl = this.faceCompareUrlValue || "/citizens/identity_submissions/face_compare"
      const resp = await fetch(compareUrl, {
        method: "POST",
        headers: { "X-CSRF-Token": csrfToken },
        body: formData
      })

      if (!resp.ok) {
        const data = await resp.json().catch(() => ({}))
        console.error("[liveness-detector] Face compare failed:", data.error)
        return { error: true }
      }

      return await resp.json()
    } catch (e) {
      console.error("[liveness-detector] Face compare network error:", e)
      return { error: true }
    }
  }

  // Finds the ID photo file from Step 1 form inputs (CIN front or Passport).
  // Falls back to cached file for mobile iOS where hidden inputs lose files.
  _getIdPhotoFile() {
    const form = this.element.closest("form")
    if (form) {
      // Check which ID type is selected
      const idTypeSelect = form.querySelector("#id_type_select")
      const idType = idTypeSelect?.value

      if (idType === "cin") {
        const cinInput = form.querySelector("input[name='identity_submission[cin_front]']")
        if (cinInput?.files?.length > 0) return cinInput.files[0]
      } else if (idType === "passport") {
        const passportInput = form.querySelector("input[name='identity_submission[passport]']")
        if (passportInput?.files?.length > 0) return passportInput.files[0]
      }

      // Fallback: try both inputs
      const cinInput = form.querySelector("input[name='identity_submission[cin_front]']")
      if (cinInput?.files?.length > 0) return cinInput.files[0]

      const passportInput = form.querySelector("input[name='identity_submission[passport]']")
      if (passportInput?.files?.length > 0) return passportInput.files[0]
    }

    // Final fallback: cached file (iOS Safari clears hidden file inputs)
    if (this._cachedIdPhoto) {
      console.info("[liveness-detector] Using cached ID photo (live input was empty)")
      return this._cachedIdPhoto
    }

    return null
  }

  // ── UI States ──

  _showComparingState() {
    if (!this.hasStatusMessageTarget) return
    const dark = this._isDarkMode()
    const bg = dark ? "#0a0f1f" : "transparent"
    const iconBg = dark ? "rgba(255,255,255,0.08)" : "#e6ecf6"
    const iconColor = dark ? "#7b8fff" : "#00209f"
    const titleColor = dark ? "#ffffff" : "#00209f"
    const descColor = dark ? "#d0d4e0" : "#666"
    this.statusMessageTarget.innerHTML = `
      <div style="text-align:center; padding: clamp(2rem, 6vw, 3rem) 1rem; font-family: 'Montserrat', sans-serif; background:${bg};">
        <div style="width:60px; height:60px; border-radius:50%; background:${iconBg};
                    display:flex; align-items:center; justify-content:center; margin:0 auto 1rem;">
          <i class="ri-loader-4-line spin" style="font-size:1.6rem; color:${iconColor};"></i>
        </div>
        <p style="font-size: clamp(0.95rem, 3vw, 1.1rem); font-weight:700; color:${titleColor}; margin-bottom:0.3rem;">
          Konparezon figi w ap fèt...
        </p>
        <p style="font-size: clamp(0.78rem, 2.3vw, 0.85rem); color:${descColor}; margin-bottom:0; line-height:1.5;">
          N ap verifye figi ou matche ak foto idantite ou.
        </p>
      </div>
    `
  }

  _showSuccessState(similarity) {
    if (!this.hasStatusMessageTarget) return
    const dark = this._isDarkMode()
    const bg = dark ? "#0a0f1f" : "transparent"
    const iconBg = dark ? "rgba(25,135,84,0.15)" : "#e8f5e9"
    const iconColor = dark ? "#34d399" : "#198754"
    const titleColor = dark ? "#34d399" : "#198754"
    const descColor = dark ? "#d0d4e0" : "#666"
    this.statusMessageTarget.innerHTML = `
      <div style="text-align:center; padding: clamp(2rem, 6vw, 3rem) 1rem; font-family: 'Montserrat', sans-serif; background:${bg};">
        <div style="width:60px; height:60px; border-radius:50%; background:${iconBg};
                    display:flex; align-items:center; justify-content:center; margin:0 auto 1rem;">
          <i class="ri-checkbox-circle-fill" style="font-size:1.6rem; color:${iconColor};"></i>
        </div>
        <p style="font-size: clamp(0.95rem, 3vw, 1.1rem); font-weight:700; color:${titleColor}; margin-bottom:0.3rem;">
          Idantite'w Verifye
        </p>
        <p style="font-size: clamp(0.78rem, 2.3vw, 0.85rem); color:${descColor}; margin-bottom:1.25rem; line-height:1.5;">
          Verifikasyon konfime epi figi ou matche ak foto idantite ou.
        </p>
        <button type="button" class="btn btn-success rounded-pill px-5 py-2 fw-bold"
                style="font-size: clamp(0.85rem, 2.5vw, 0.95rem); font-family: Montserrat, sans-serif;"
                data-action="wizard#next">
          Kontinye <i class="ri-arrow-right-line ms-1"></i>
        </button>
      </div>
    `
  }

  // Error state — AWS or network error, BLOCKS progression (user must retry)
  _showErrorState() {
    if (!this.hasStatusMessageTarget) return
    const dark = this._isDarkMode()
    const bg = dark ? "#0a0f1f" : "transparent"
    const iconBg = dark ? "rgba(245,158,11,0.15)" : "#fef3c7"
    const iconColor = dark ? "#fbbf24" : "#d97706"
    const titleColor = dark ? "#fbbf24" : "#d97706"
    const descColor = dark ? "#d0d4e0" : "#666"
    this.statusMessageTarget.innerHTML = `
      <div style="text-align:center; padding: clamp(2rem, 6vw, 3rem) 1rem; font-family: 'Montserrat', sans-serif; background:${bg};">
        <div style="width:60px; height:60px; border-radius:50%; background:${iconBg};
                    display:flex; align-items:center; justify-content:center; margin:0 auto 1rem;">
          <i class="ri-error-warning-fill" style="font-size:1.6rem; color:${iconColor};"></i>
        </div>
        <p style="font-size: clamp(0.95rem, 3vw, 1.1rem); font-weight:700; color:${titleColor}; margin-bottom:0.3rem;">
          Verifikasyon pa t kapab fèt
        </p>
        <p style="font-size: clamp(0.78rem, 2.3vw, 0.85rem); color:${titleColor}; margin-bottom:1.25rem; line-height:1.5;">
          Nou pa t kapab konpare figi ou ak foto idantite ou pou kounye a. Tanpri eseye ankò.
        </p>
        <button type="button" class="btn btn-outline-light btn-sm rounded-pill px-4"
                style="font-size: clamp(0.8rem, 2.5vw, 0.875rem); font-family: Montserrat, sans-serif; font-weight: 600;"
                data-action="liveness-detector#retry">
          <i class="ri-refresh-line me-1"></i> Eseye ankò
        </button>
      </div>
    `
  }

  // After face match passes, hide all Back/Previous buttons on Step 2
  // so the user can only go forward. Going back would invalidate the match.
  _hideStepBackButtons() {
    const step = this.element.closest("[data-wizard-target='step']")
    if (!step) return
    // Hide the step-level Back button outside the liveness card
    const backBtns = step.querySelectorAll("[data-action='wizard#previous'], [data-action='wizard#goToStep'][data-step='1']")
    backBtns.forEach(btn => { btn.style.display = "none" })
  }

  // Clean up sessionStorage cache after successful face match
  _clearIdPhotoCache() {
    try {
      sessionStorage.removeItem("bonid_id_photo_data")
      sessionStorage.removeItem("bonid_id_photo_name")
      sessionStorage.removeItem("bonid_id_photo_type")
    } catch (e) { /* ignore */ }
  }

  _showMismatchState(message) {
    if (!this.hasStatusMessageTarget) return
    const dark = this._isDarkMode()
    const bg = dark ? "#0a0f1f" : "transparent"
    const iconBg = dark ? "rgba(220,53,69,0.15)" : "#fef2f2"
    const iconColor = dark ? "#f87171" : "#dc3545"
    const titleColor = dark ? "#f87171" : "#dc3545"
    const descColor = dark ? "#d0d4e0" : "#666"
    const safeMessage = this._escapeHtml(message || "Figi ou pa matche ak foto ki sou dokiman an.")
    this.statusMessageTarget.innerHTML = `
      <div style="text-align:center; padding: clamp(2rem, 6vw, 3rem) 1rem; font-family: 'Montserrat', sans-serif; background:${bg};">
        <div style="width:60px; height:60px; border-radius:50%; background:${iconBg};
                    display:flex; align-items:center; justify-content:center; margin:0 auto 1rem;">
          <i class="ri-close-circle-fill" style="font-size:1.6rem; color:${iconColor};"></i>
        </div>
        <p style="font-size: clamp(0.95rem, 3vw, 1.1rem); font-weight:700; color:${titleColor}; margin-bottom:0.3rem;">
          Figi ou pa matche ak dokiman an
        </p>
        <p style="font-size: clamp(0.78rem, 2.3vw, 0.85rem); color:${titleColor}; margin-bottom:0.5rem; line-height:1.5;">
          ${safeMessage}
        </p>
        <p style="font-size: clamp(0.75rem, 2.2vw, 0.82rem); color:${titleColor}; opacity:0.85; margin-bottom:1.25rem; line-height:1.5;">
          Tanpri retounen nan <strong>Etap 1</strong> epi telechaje yon dokiman idantite valab ak foto ou, epi eseye ankò.
        </p>
        <div style="display: flex; gap: 0.75rem; justify-content: center; flex-wrap: wrap;">
          <button type="button" class="btn btn-outline-light btn-sm rounded-pill px-4"
                  style="font-size: clamp(0.8rem, 2.5vw, 0.875rem); font-family: Montserrat, sans-serif; font-weight: 600;"
                  data-action="wizard#goToStep" data-step="1">
            <i class="ri-arrow-left-line me-1"></i> Retounen Etap 1
          </button>
          <button type="button" class="btn btn-sm rounded-pill px-4"
                  style="font-size: clamp(0.8rem, 2.5vw, 0.875rem); font-family: Montserrat, sans-serif; font-weight: 600; background: rgba(255,255,255,0.15); color: #fff; border: 1px solid rgba(255,255,255,0.25);"
                  data-action="liveness-detector#retry">
            <i class="ri-refresh-line me-1"></i> Eseye ankò
          </button>
        </div>
      </div>
    `
  }

  _isDarkMode() {
    return !!this.element.closest(".bonid-liveness-dark") || !!this.element.closest(".consent-liveness-dark")
  }

  _escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }

  // ── Attempt Tracker Persistence ──

  _loadAttemptTracker() {
    try {
      const stored = sessionStorage.getItem("bonid_liveness_attempts")
      if (stored) {
        const data = JSON.parse(stored)
        const windowMs = 3 * 60 * 1000
        const now = Date.now()
        data.attempts = (data.attempts || []).filter(t => now - t < windowMs)
        return data
      }
    } catch (e) { /* ignore */ }
    return { attempts: [] }
  }

  _saveAttemptTracker() {
    try {
      sessionStorage.setItem("bonid_liveness_attempts", JSON.stringify(this._attemptTracker))
    } catch (e) { /* ignore */ }
  }
}
