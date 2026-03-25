import { Controller } from "@hotwired/stimulus"

// Manages the focus card for active transaction consent requests.
// Handles countdown timer, audio notification ping, and connection status.
export default class extends Controller {
  static targets = [
    "progressBar",
    "countdown",
    "connectionDot",
    "connectionLabel",
    "focusCard"
  ]

  static values = {
    expiresAt: String,
    soundUrl: { type: String, default: "" }
  }

  connect() {
    this.startCountdown()
    this.playNotificationSound()
    this.monitorConnection()
  }

  // ─────────────────────────────────────────────
  // COUNTDOWN — real expires_at, not artificial
  // ─────────────────────────────────────────────
  startCountdown() {
    const expiresAt = new Date(this.expiresAtValue).getTime()
    const now = Date.now()
    this.totalSeconds = Math.max(1, Math.floor((expiresAt - now) / 1000))

    this._tick(expiresAt)
    this.timer = setInterval(() => this._tick(expiresAt), 1000)
  }

  _tick(expiresAt) {
    const remaining = Math.max(0, Math.floor((expiresAt - Date.now()) / 1000))
    const pct = Math.max(0, (remaining / this.totalSeconds) * 100)

    if (this.hasProgressBarTarget) {
      this.progressBarTarget.style.width = `${pct}%`

      // Urgent color when under 60 seconds
      if (remaining <= 60) {
        this.progressBarTarget.style.background = "#dc3545"
      }
    }

    if (this.hasCountdownTarget) {
      const mins = Math.floor(remaining / 60)
      const secs = remaining % 60
      if (mins > 0) {
        this.countdownTarget.textContent = `${mins}m ${secs}s remaining`
      } else {
        this.countdownTarget.textContent = `${secs}s remaining`
      }
    }

    if (remaining <= 0) {
      clearInterval(this.timer)
      this._handleExpiry()
    }
  }

  _handleExpiry() {
    if (this.hasFocusCardTarget) {
      this.focusCardTarget.style.opacity = "0.5"
      this.focusCardTarget.style.pointerEvents = "none"
    }
    if (this.hasCountdownTarget) {
      this.countdownTarget.textContent = "Expired"
    }
  }

  // ─────────────────────────────────────────────
  // AUDIO NOTIFICATION — ping on new consent
  // ─────────────────────────────────────────────
  playNotificationSound() {
    if (!this.soundUrlValue) return

    try {
      const audio = new Audio(this.soundUrlValue)
      audio.volume = 0.6
      audio.play().catch(() => {
        // Autoplay blocked — sound will play on subsequent consents
        // after user has interacted with the page
      })
    } catch (_e) {
      // Silent fail for browsers that don't support Audio
    }
  }

  // ─────────────────────────────────────────────
  // CONNECTION STATUS — monitor ActionCable state
  // ─────────────────────────────────────────────
  monitorConnection() {
    this._updateConnectionUI(true) // optimistic
    this.connectionTimer = setInterval(() => {
      let connected = false
      try {
        // turbo-rails exposes cable consumer at Turbo.cable
        const cable = window.Turbo?.cable
        if (cable?.connection) {
          connected = cable.connection.isOpen?.() ?? false
        }
      } catch (_e) {
        connected = false
      }
      this._updateConnectionUI(connected)
    }, 3000)
  }

  _updateConnectionUI(connected) {
    if (this.hasConnectionDotTarget) {
      this.connectionDotTarget.style.background = connected ? "#198754" : "#ffc107"
      this.connectionDotTarget.style.animationName = connected ? "pulse-live" : "none"
    }
    if (this.hasConnectionLabelTarget) {
      this.connectionLabelTarget.textContent = connected ? "Live" : "Reconnecting..."
      this.connectionLabelTarget.style.color = connected ? "#198754" : "#ffc107"
    }
  }

  // ─────────────────────────────────────────────
  // CLEANUP
  // ─────────────────────────────────────────────
  disconnect() {
    if (this.timer) clearInterval(this.timer)
    if (this.connectionTimer) clearInterval(this.connectionTimer)
  }
}
