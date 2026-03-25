import { Controller } from "@hotwired/stimulus"

// Bridges the React FaceLivenessDetector with the transaction consent
// approval flow. Uses the same React component (liveness.jsx) as the
// BonID identity submission — including GetReady screen, rate limiting,
// error handling, and low-bandwidth fallback.
export default class extends Controller {
  static targets = ["mountPoint", "statusMessage"]

  static values = {
    consentToken: String,
    decideUrl: String,
    region: { type: String, default: "us-east-1" },
    identityPoolId: { type: String, default: "" }
  }

  connect() {
    this.passed = false
    this._attemptTracker = this._loadAttemptTracker()
    this._loadConfigFromMeta()
  }

  disconnect() {
    window.BonidLiveness?.unmount()
  }

  // ─────────────────────────────────────────────
  // START LIVENESS — mount the React component
  // ─────────────────────────────────────────────
  startLiveness(event) {
    event.preventDefault()
    if (this.passed) return

    // Show the liveness overlay and hide navbar
    document.body.classList.add("liveness-active")
    const mountContainer = document.getElementById("consent-liveness-mount")
    if (mountContainer) {
      mountContainer.classList.remove("d-none")
    }

    if (!window.BonidLiveness) {
      this._showStatus("Preparasyon verifikasyon figi...", "text-muted")
      setTimeout(() => this.startLiveness(event), 500)
      return
    }

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    const mountEl = this.hasMountPointTarget
      ? this.mountPointTarget
      : document.getElementById("consent-liveness-react-mount")

    // Mount with FULL options — same as identity submission controller
    window.BonidLiveness.mount(mountEl, {
      csrfToken,
      region: this.regionValue,
      identityPoolId: this.identityPoolIdValue,
      attemptTracker: this._attemptTracker,
      onComplete: (data) => this._handleComplete(data),
      onError: (data) => this._handleError(data)
    })
  }

  // ─────────────────────────────────────────────
  // CALLBACKS
  // ─────────────────────────────────────────────
  async _handleComplete(data) {
    this.passed = true

    // Clear attempts on success
    this._attemptTracker.attempts = []
    this._saveAttemptTracker()

    this._showStatus("Ap apwouve tranzaksyon an...", "text-success")

    const sessionId = data.session_id || data.sessionId || data.blob_signed_id
    if (!sessionId) {
      this._handleError({ message: "Missing liveness session ID" })
      return
    }

    try {
      const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

      const resp = await fetch(this.decideUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "text/vnd.turbo-stream.html, text/html"
        },
        body: JSON.stringify({
          liveness_session_id: sessionId,
          decision: "approve"
        })
      })

      if (resp.ok) {
        const html = await resp.text()
        Turbo.renderStreamMessage(html)
        this._hideLivenessMount()
      } else {
        this._showStatus("Verifikasyon echwe. Eseye itilize yon kòd pito.", "text-danger")
        this.passed = false
      }
    } catch (err) {
      console.error("[consent-liveness] Network error:", err)
      this._showStatus("Erè koneksyon. Eseye itilize yon kòd pito.", "text-danger")
      this.passed = false
    }
  }

  _handleError(data) {
    this.passed = false
    // Track attempts (React component handles its own error UI)
    this._attemptTracker.attempts = [...(this._attemptTracker.attempts || []), Date.now()]
    this._saveAttemptTracker()
  }

  // ─────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────
  _showStatus(text, cssClass) {
    const el = this.hasStatusMessageTarget
      ? this.statusMessageTarget
      : document.getElementById("consent-liveness-status")
    if (el) {
      el.textContent = text
      el.className = `liveness-status ${cssClass}`
      el.style.textAlign = "center"
      el.style.width = "100%"
      el.style.fontSize = "1rem"
      el.style.fontWeight = "600"
      el.style.fontFamily = "'Montserrat', sans-serif"
    }
  }

  _hideLivenessMount() {
    document.body.classList.remove("liveness-active")
    const mountContainer = document.getElementById("consent-liveness-mount")
    if (mountContainer) {
      mountContainer.classList.add("d-none")
    }
    window.BonidLiveness?.unmount()
  }

  _loadConfigFromMeta() {
    const regionMeta = document.querySelector("meta[name='aws-region']")
    const poolMeta = document.querySelector("meta[name='aws-identity-pool-id']")
    if (regionMeta) this.regionValue = regionMeta.content
    if (poolMeta) this.identityPoolIdValue = poolMeta.content
  }

  // ── Attempt Tracker Persistence ──
  _loadAttemptTracker() {
    try {
      const stored = sessionStorage.getItem("bonid_consent_liveness_attempts")
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
      sessionStorage.setItem("bonid_consent_liveness_attempts", JSON.stringify(this._attemptTracker))
    } catch (e) { /* ignore */ }
  }
}
