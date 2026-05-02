import { Controller } from "@hotwired/stimulus"

// Segmented OTP input with auto-advance, paste support, countdown timer,
// resend cooldown, and an error-shake animation.
//
// Markup:
//   <div data-controller="otp-input"
//        data-otp-input-length-value="6"
//        data-otp-input-expires-at-value="1714694400"
//        data-otp-input-resend-after-seconds-value="60">
//
//     <div class="otp-input-row" data-otp-input-target="row">
//       <input data-otp-input-target="box" inputmode="numeric" maxlength="1" pattern="\d">
//       ...repeat 6 times
//     </div>
//
//     <input type="hidden" name="user[email_change_code]"
//            data-otp-input-target="hidden">
//
//     <span data-otp-input-target="timer"></span>
//     <button data-otp-input-target="resend" hidden>Voye l ankò</button>
//   </div>
export default class extends Controller {
  static targets = ["row", "box", "hidden", "timer", "resend"]
  static values = {
    length:             { type: Number, default: 6 },
    expiresAt:          { type: Number, default: 0 },   // unix seconds, optional
    resendAfterSeconds: { type: Number, default: 60 }
  }

  connect() {
    if (this.hasBoxTarget && this.boxTargets.length > 0) {
      // Auto-focus first empty box
      const first = this.boxTargets.find((b) => !b.value) || this.boxTargets[0]
      // requestAnimationFrame so modal fade-in finishes before focus
      requestAnimationFrame(() => first.focus())
    }
    this._startCountdown()
    this._startResendCooldown()
  }

  disconnect() {
    if (this._timerInt)  clearInterval(this._timerInt)
    if (this._resendT)   clearTimeout(this._resendT)
  }

  // ── Box input handlers ──────────────────────────────────────────────

  onInput(event) {
    const box = event.target
    const v = box.value.replace(/\D/g, "").slice(-1) // keep only last digit
    box.value = v
    box.classList.remove("is-invalid")
    if (v) {
      const next = this._nextBox(box)
      if (next) next.focus()
    }
    this._syncHidden()
  }

  onKeydown(event) {
    const box = event.target
    if (event.key === "Backspace" && !box.value) {
      const prev = this._prevBox(box)
      if (prev) {
        prev.focus()
        prev.value = ""
        this._syncHidden()
        event.preventDefault()
      }
      return
    }
    if (event.key === "ArrowLeft") {
      const prev = this._prevBox(box)
      if (prev) { prev.focus(); event.preventDefault() }
      return
    }
    if (event.key === "ArrowRight") {
      const next = this._nextBox(box)
      if (next) { next.focus(); event.preventDefault() }
      return
    }
  }

  onPaste(event) {
    const text = (event.clipboardData || window.clipboardData)?.getData("text") || ""
    const digits = text.replace(/\D/g, "").split("").slice(0, this.lengthValue)
    if (digits.length === 0) return
    event.preventDefault()
    this.boxTargets.forEach((b, i) => {
      b.value = digits[i] || ""
      b.classList.remove("is-invalid")
    })
    this._syncHidden()
    const last = this.boxTargets[Math.min(digits.length, this.lengthValue) - 1]
    if (last) last.focus()
  }

  // ── Internals ───────────────────────────────────────────────────────

  _syncHidden() {
    if (!this.hasHiddenTarget) return
    this.hiddenTarget.value = this.boxTargets.map((b) => b.value).join("")
  }

  _nextBox(box) {
    const idx = this.boxTargets.indexOf(box)
    return this.boxTargets[idx + 1] || null
  }

  _prevBox(box) {
    const idx = this.boxTargets.indexOf(box)
    return this.boxTargets[idx - 1] || null
  }

  // Adds a brief shake + red border on every box. Public so the form's
  // turbo:submit-end (or a server-rendered error flash) can call it.
  flagInvalid() {
    this.boxTargets.forEach((b) => b.classList.add("is-invalid"))
    if (!this.element.classList.contains("otp-shake")) {
      this.element.classList.add("otp-shake")
      setTimeout(() => this.element.classList.remove("otp-shake"), 360)
    }
    if (this.boxTargets[0]) this.boxTargets[0].focus()
  }

  // ── Countdown ───────────────────────────────────────────────────────

  _startCountdown() {
    if (!this.hasTimerTarget || !this.expiresAtValue) return
    const tick = () => {
      const remaining = this.expiresAtValue - Math.floor(Date.now() / 1000)
      if (remaining <= 0) {
        this.timerTarget.textContent = "Kòd la ekspire."
        this.timerTarget.classList.remove("text-bg-light", "text-bg-warning")
        this.timerTarget.classList.add("text-bg-danger")
        clearInterval(this._timerInt)
        return
      }
      // Switch to amber under 1 minute — subtle urgency without alarm.
      if (remaining < 60) {
        this.timerTarget.classList.remove("text-bg-light")
        this.timerTarget.classList.add("text-bg-warning")
      }
      const m = Math.floor(remaining / 60)
      const s = remaining % 60
      this.timerTarget.textContent =
        `Kòd la ap ekspire nan ${m}:${s.toString().padStart(2, "0")}`
    }
    tick()
    this._timerInt = setInterval(tick, 1000)
  }

  // ── Resend ──────────────────────────────────────────────────────────

  _startResendCooldown() {
    if (!this.hasResendTarget) return
    const wait = Math.max(1, this.resendAfterSecondsValue) * 1000
    this.resendTarget.hidden = true
    this._resendT = setTimeout(() => {
      this.resendTarget.hidden = false
    }, wait)
  }
}
