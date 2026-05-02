import { Controller } from "@hotwired/stimulus"

// Persist citizen wizard form values to localStorage so a refresh,
// accidental tab-close, or dead phone battery doesn't blow away
// progress. Auto-attaches to every text/select/textarea inside the
// controller's element so views don't need per-field tagging.
//
// Markup:
//   <div data-controller="wizard-persistence"
//        data-wizard-persistence-key-value="profile-edit"
//        data-action="submit->wizard-persistence#clear">
//     ...form fields...
//   </div>
//
// Excludes:
//   - File inputs (browser security — can't restore <input type="file">)
//   - Password / OTP / CSRF / authenticity_token / _method
//   - Hidden inputs (these are server-controlled state, not user input)
//   - Signature drawn data URLs (huge blobs)
//   - Anything matching the SENSITIVE_PATTERN regex below
//
// localStorage record is auto-expired after EXPIRES_AFTER_MS so a stale
// draft from weeks ago doesn't repopulate a fresh form.
export default class extends Controller {
  static values = {
    key:           { type: String, default: "default" },
    expiresAfterMs: { type: Number, default: 24 * 60 * 60 * 1000 } // 24h
  }

  // Field names / types we never persist. Citizens may type secrets into
  // these and we don't want them sitting in localStorage.
  static SENSITIVE_PATTERN = /(password|otp|token|csrf|_method|signature|selfie|secret|pin)/i
  static SENSITIVE_TYPES = new Set([ "password", "file", "hidden", "submit", "button", "image", "reset" ])

  connect() {
    this._debouncedSave = this._debounce(() => this.save(), 400)
    this._handler = (e) => this._onChange(e)

    // Listen at controller-element level so dynamically added inputs are
    // covered without re-binding.
    this.element.addEventListener("input", this._handler)
    this.element.addEventListener("change", this._handler)

    this._buildToast()
    this.restore()
  }

  disconnect() {
    this.element.removeEventListener("input", this._handler)
    this.element.removeEventListener("change", this._handler)
    if (this._toastEl) this._toastEl.remove()
  }

  // Called by the host form's submit action — wipes the draft once the
  // wizard is genuinely complete so a future fresh start doesn't inherit it.
  clear() {
    try { localStorage.removeItem(this._storageKey) } catch (_) { /* quota / disabled */ }
  }

  // Manual save trigger if a view wants to force a write (e.g. on step change).
  save() {
    const fields = this._collectFields()
    if (Object.keys(fields).length === 0) return

    const payload = { savedAt: Date.now(), fields }
    try {
      localStorage.setItem(this._storageKey, JSON.stringify(payload))
      this._showToast()
    } catch (_) { /* quota / disabled — silent */ }
  }

  restore() {
    let payload
    try { payload = JSON.parse(localStorage.getItem(this._storageKey) || "null") }
    catch (_) { return }
    if (!payload || !payload.fields) return

    // Drop drafts older than the expiry window
    if (typeof payload.savedAt === "number" &&
        Date.now() - payload.savedAt > this.expiresAfterMsValue) {
      this.clear()
      return
    }

    this._eachField((input) => {
      const stored = payload.fields[input.name]
      if (stored === undefined) return

      // Don't clobber a value the citizen already typed in this session
      // (e.g. browser autofill arrived first).
      if (this._currentValue(input) !== "" && this._currentValue(input) !== false) return

      if (input.type === "checkbox") {
        input.checked = !!stored
      } else if (input.type === "radio") {
        if (input.value === stored) input.checked = true
      } else {
        input.value = stored
      }
    })
  }

  // ── private ──

  _onChange(event) {
    const t = event.target
    if (!t || !t.name) return
    if (this._isSensitive(t)) return
    this._debouncedSave()
  }

  _collectFields() {
    const data = {}
    this._eachField((input) => {
      if (input.type === "checkbox") {
        data[input.name] = input.checked
      } else if (input.type === "radio") {
        if (input.checked) data[input.name] = input.value
      } else {
        const v = input.value
        if (v !== "" && v != null) data[input.name] = v
      }
    })
    return data
  }

  _eachField(fn) {
    const inputs = this.element.querySelectorAll("input, select, textarea")
    inputs.forEach((input) => {
      if (this._isSensitive(input)) return
      if (!input.name) return
      fn(input)
    })
  }

  _isSensitive(input) {
    if (!input || !input.tagName) return true
    const type = (input.type || "").toLowerCase()
    if (this.constructor.SENSITIVE_TYPES.has(type)) return true
    const name = (input.name || "").toLowerCase()
    if (!name) return true
    if (this.constructor.SENSITIVE_PATTERN.test(name)) return true
    // Don't persist values from explicitly opted-out fields
    if (input.dataset.wizardPersistenceSkip === "true") return true
    return false
  }

  _currentValue(input) {
    if (input.type === "checkbox" || input.type === "radio") return input.checked
    return input.value
  }

  get _storageKey() {
    return `wizard-draft:${this.keyValue}:${window.location.pathname}`
  }

  _debounce(fn, wait) {
    let t = null
    return function (...args) {
      if (t) clearTimeout(t)
      t = setTimeout(() => fn.apply(this, args), wait)
    }
  }

  // Subtle bottom-right "Sove" pill that fades in for ~1.2s after a save.
  _buildToast() {
    const el = document.createElement("div")
    el.setAttribute("aria-live", "polite")
    el.style.cssText = [
      "position: fixed", "bottom: 20px", "right: 20px",
      "z-index: 1080",
      "padding: 0.45rem 0.85rem",
      "border-radius: 999px",
      "background: rgba(16, 185, 129, 0.95)",
      "color: #fff",
      "font-family: 'Montserrat', sans-serif",
      "font-size: 0.78rem",
      "font-weight: 600",
      "box-shadow: 0 4px 12px rgba(0,0,0,0.12)",
      "opacity: 0",
      "transform: translateY(8px)",
      "transition: opacity 0.2s ease, transform 0.2s ease",
      "pointer-events: none"
    ].join(";")
    el.textContent = "✓ Pwogrè ou sove"
    document.body.appendChild(el)
    this._toastEl = el
  }

  _showToast() {
    if (!this._toastEl) return
    if (this._toastTimer) clearTimeout(this._toastTimer)
    this._toastEl.style.opacity = "1"
    this._toastEl.style.transform = "translateY(0)"
    this._toastTimer = setTimeout(() => {
      this._toastEl.style.opacity = "0"
      this._toastEl.style.transform = "translateY(8px)"
    }, 1200)
  }
}
