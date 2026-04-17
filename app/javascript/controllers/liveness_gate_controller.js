import { Controller } from "@hotwired/stimulus"

// Gates the election ballot behind an Amplify liveness check. Modeled on
// consent_liveness_controller — same React component, same mount-point CSS
// — but instead of POSTing JSON, it writes the liveness session id into a
// hidden field and lets the form submit naturally to vote_controller#begin.
//
// The vote controller refuses the submission unless `liveness_session_id`
// is present, which is what prevents a citizen from voting without proving
// they're alive in front of the camera.
//
// Usage:
//   <form data-controller="liveness-gate"
//         data-action="submit->liveness-gate#startLiveness">
//     <input type="hidden" name="liveness_session_id"
//            data-liveness-gate-target="sessionId">
//     <button type="submit">Start Voting</button>
//   </form>
export default class extends Controller {
  static targets = ["form", "sessionId", "biometricHash", "statusMessage"]

  static values = {
    region: { type: String, default: "us-east-1" },
    identityPoolId: { type: String, default: "" }
  }

  connect() {
    this.passed = false
    this._submitting = false
    this._attemptTracker = this._loadAttemptTracker()
    this._loadConfigFromMeta()
  }

  disconnect() {
    window.BonidLiveness?.unmount()
  }

  // Intercepts the form submit. If liveness has already passed in this
  // session (e.g. the browser re-submitted after a server bounce), we let
  // the submission through — `passed` is set to true once we've already
  // written a session id into the hidden field.
  startLiveness(event) {
    if (this.passed) return // let the native submission proceed
    event.preventDefault()
    // Stop the submit from bubbling to document — global_loading_controller
    // listens there and would otherwise show its full-screen "Loading..."
    // overlay on top of the Amplify liveness modal with no way to dismiss it
    // (no turbo:submit-end fires because we cancelled the submission).
    event.stopPropagation()
    if (this._submitting) return

    document.body.classList.add("liveness-active")
    const mountContainer = document.getElementById("election-liveness-mount")
    mountContainer?.classList.remove("d-none")

    // BonidLiveness bundle might still be loading — retry shortly.
    if (!window.BonidLiveness) {
      this._showStatus("Preparasyon verifikasyon figi...", "text-muted")
      setTimeout(() => this.startLiveness(event), 500)
      return
    }

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    const mountEl = document.getElementById("election-liveness-react-mount")

    window.BonidLiveness.mount(mountEl, {
      csrfToken,
      region: this.regionValue,
      identityPoolId: this.identityPoolIdValue,
      attemptTracker: this._attemptTracker,
      onComplete: (data) => this._handleComplete(data),
      onError: (data) => this._handleError(data)
    })
  }

  _handleComplete(data) {
    this._attemptTracker.attempts = []
    this._saveAttemptTracker()

    const sessionId = data.session_id || data.sessionId || data.blob_signed_id
    if (!sessionId) {
      this._handleError({ message: "Missing liveness session ID" })
      return
    }

    // Write the session into the hidden field and resubmit the form —
    // this time `passed` is true so startLiveness lets it through.
    if (this.hasSessionIdTarget) {
      this.sessionIdTarget.value = sessionId
    }
    if (this.hasBiometricHashTarget && data.biometric_hash) {
      this.biometricHashTarget.value = data.biometric_hash
    }

    this.passed = true
    this._submitting = true
    this._showStatus("Verifikasyon reyisi. Ap ale nan bilten vòt...", "text-success")
    this._hideLivenessMount()

    const form = this.hasFormTarget ? this.formTarget : this.element
    form.requestSubmit ? form.requestSubmit() : form.submit()
  }

  _handleError(data) {
    this.passed = false
    this._attemptTracker.attempts = [...(this._attemptTracker.attempts || []), Date.now()]
    this._saveAttemptTracker()
  }

  _showStatus(text, cssClass) {
    const el = this.hasStatusMessageTarget
      ? this.statusMessageTarget
      : document.getElementById("election-liveness-status")
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
    const mountContainer = document.getElementById("election-liveness-mount")
    mountContainer?.classList.add("d-none")
    window.BonidLiveness?.unmount()
  }

  _loadConfigFromMeta() {
    const regionMeta = document.querySelector("meta[name='aws-region']")
    const poolMeta = document.querySelector("meta[name='aws-identity-pool-id']")
    if (regionMeta) this.regionValue = regionMeta.content
    if (poolMeta) this.identityPoolIdValue = poolMeta.content
  }

  // ── Attempt Tracker Persistence ──
  // Re-uses the same 3-minute rolling window the consent flow uses so a
  // voter who already blew through attempts on a consent today doesn't
  // get a second fresh budget on the voting page.
  _loadAttemptTracker() {
    try {
      const stored = sessionStorage.getItem("bonid_election_liveness_attempts")
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
      sessionStorage.setItem("bonid_election_liveness_attempts", JSON.stringify(this._attemptTracker))
    } catch (e) { /* ignore */ }
  }
}
