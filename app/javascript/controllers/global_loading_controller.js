// app/javascript/controllers/global_loading_controller.js
import { Controller } from "@hotwired/stimulus"

/**
 * GlobalLoadingController — Page-Ready Loading Overlay
 *
 * The overlay starts VISIBLE in the HTML (no d-none). This controller
 * hides it once the page is fully loaded and ready to display.
 *
 * Covers ALL scenarios:
 *   - Turbo Drive page navigation (links)
 *   - Turbo form submissions
 *   - Non-Turbo form submissions (data-turbo="false")
 *   - Non-Turbo link clicks (logout, password reset, etc.)
 *   - Direct URL visits / first page load
 *   - Network errors and HTTP 5xx errors
 *
 * Failsafe: <noscript> tag in HTML hides overlay if JS is disabled.
 *
 * Usage: data-controller="global-loading" on <body>
 *        Include shared/_global_loading.html.erb partial
 */
export default class extends Controller {
  static targets = ["overlay", "spinner", "ring", "text"]
  static values = {
    delay: { type: Number, default: 200 },      // ms before showing (Turbo navigation)
    minDisplay: { type: Number, default: 800 }   // minimum display time
  }

  connect() {
    this.isLoading = false
    this.showTimeout = null
    this.hideTimeout = null
    this.errorTimeout = null
    this.displayedAt = null // overlay starts hidden

    // ── Turbo event listeners ──
    this.handleClick = this.handleClick.bind(this)
    this.handleSubmitStart = this.handleSubmitStart.bind(this)
    this.handleLoad = this.handleLoad.bind(this)
    this.handleSubmitEnd = this.handleSubmitEnd.bind(this)
    this.handleBeforeCache = this.handleBeforeCache.bind(this)
    this.handleRender = this.handleRender.bind(this)

    document.addEventListener("turbo:click", this.handleClick)
    document.addEventListener("turbo:submit-start", this.handleSubmitStart)
    document.addEventListener("turbo:load", this.handleLoad)
    document.addEventListener("turbo:render", this.handleRender)
    document.addEventListener("turbo:submit-end", this.handleSubmitEnd)
    document.addEventListener("turbo:before-cache", this.handleBeforeCache)

    // ── Error listeners ──
    this.handleFetchError = this.handleFetchError.bind(this)
    this.handleFetchResponse = this.handleFetchResponse.bind(this)

    document.addEventListener("turbo:fetch-request-error", this.handleFetchError)
    document.addEventListener("turbo:before-fetch-response", this.handleFetchResponse)

    // ── Non-Turbo listeners ──
    this.handleNativeSubmit = this.handleNativeSubmit.bind(this)
    this.handleNativeLinkClick = this.handleNativeLinkClick.bind(this)

    document.addEventListener("submit", this.handleNativeSubmit)
    document.addEventListener("click", this.handleNativeLinkClick)
  }

  disconnect() {
    document.removeEventListener("turbo:click", this.handleClick)
    document.removeEventListener("turbo:submit-start", this.handleSubmitStart)
    document.removeEventListener("turbo:load", this.handleLoad)
    document.removeEventListener("turbo:render", this.handleRender)
    document.removeEventListener("turbo:submit-end", this.handleSubmitEnd)
    document.removeEventListener("turbo:before-cache", this.handleBeforeCache)
    document.removeEventListener("turbo:fetch-request-error", this.handleFetchError)
    document.removeEventListener("turbo:before-fetch-response", this.handleFetchResponse)
    document.removeEventListener("submit", this.handleNativeSubmit)
    document.removeEventListener("click", this.handleNativeLinkClick)

    this.forceHide()
  }

  // ═══════════════════════════════════════════
  // TURBO EVENT HANDLERS
  // ═══════════════════════════════════════════

  handleClick(event) {
    const link = event.target

    if (link?.target === "_blank") return
    if (link?.dataset?.turbo === "false") return
    if (link?.closest?.('[data-turbo="false"]')) return
    if (link?.getAttribute?.("href")?.startsWith("#")) return

    this.startLoading()
  }

  handleSubmitStart(event) {
    const form = event.target

    if (form?.dataset?.turbo === "false") return
    if (form?.closest?.('[data-turbo="false"]')) return
    if (form?.closest?.("turbo-frame")) return

    this.startLoading()
  }

  handleLoad() {
    this.stopLoading()
  }

  handleRender() {
    this.stopLoading()
  }

  handleSubmitEnd() {
    this.stopLoading()
  }

  handleBeforeCache() {
    // Hide instantly before Turbo caches the page (no d-none added to cache)
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.remove("bonid-loading-visible")
      this.overlayTarget.classList.add("d-none")
      this.overlayTarget.setAttribute("aria-hidden", "true")
    }
    if (this.showTimeout) clearTimeout(this.showTimeout)
    if (this.hideTimeout) clearTimeout(this.hideTimeout)
    if (this.errorTimeout) clearTimeout(this.errorTimeout)
    if (this.failsafeTimeout) clearTimeout(this.failsafeTimeout)
    this.showTimeout = null
    this.hideTimeout = null
    this.errorTimeout = null
    this.failsafeTimeout = null
    this.isLoading = false
    this.displayedAt = null
  }

  // ═══════════════════════════════════════════
  // NON-TURBO EVENT HANDLERS
  // ═══════════════════════════════════════════

  handleNativeSubmit(event) {
    const form = event.target
    if (!form || form.tagName !== "FORM") return

    // A JS handler (fetch / preventDefault) is taking over this submission — no
    // navigation will happen, so showing the overlay would leave it stuck. Skip.
    if (event.defaultPrevented) return

    // Only handle forms with data-turbo="false"
    const isTurboDisabled =
      form.dataset?.turbo === "false" ||
      !!form.closest('[data-turbo="false"]')

    if (!isTurboDisabled) return

    // Show overlay immediately — browser is about to navigate
    this.show()
    this.isLoading = true
  }

  handleNativeLinkClick(event) {
    const link = event.target?.closest?.("a[href]")
    if (!link) return

    // A JS handler already took over this click — no navigation, skip the overlay.
    if (event.defaultPrevented) return

    // Only handle links/containers with data-turbo="false"
    const isTurboDisabled =
      link.dataset?.turbo === "false" ||
      !!link.closest('[data-turbo="false"]')

    if (!isTurboDisabled) return

    // Skip anchors, new tabs, javascript: links
    const href = link.getAttribute("href")
    if (!href || href.startsWith("#") || href.startsWith("javascript:")) return
    if (link.target === "_blank") return

    // Skip links inside forms (button_to generates a form around the link)
    if (link.closest("form")) return

    // Show overlay immediately
    this.show()
    this.isLoading = true
  }

  // ═══════════════════════════════════════════
  // ERROR HANDLERS
  // ═══════════════════════════════════════════

  handleFetchError() {
    this.showError("Connection error. Please check your internet and try again.")
  }

  handleFetchResponse(event) {
    const response = event.detail?.fetchResponse?.response
    if (!response) return

    const status = response.status

    // Server errors (5xx)
    if (status >= 500) {
      this.showError("Something went wrong. Please try again.")
    }
    // 4xx errors: let Turbo render the response page (validation errors etc.)
  }

  // ═══════════════════════════════════════════
  // SHOW / HIDE LOGIC
  // ═══════════════════════════════════════════

  startLoading() {
    if (this.isLoading) return
    this.isLoading = true

    // Clear any pending hide
    if (this.hideTimeout) {
      clearTimeout(this.hideTimeout)
      this.hideTimeout = null
    }

    // Clear any error state
    this.clearError()

    // Don't schedule if already visible
    if (this.isVisible()) return

    // Delay showing to avoid flicker on fast Turbo requests
    this.showTimeout = setTimeout(() => {
      this.showTimeout = null
      if (this.isLoading) {
        this.show()
      }
    }, this.delayValue)
  }

  stopLoading() {
    this.isLoading = false

    // Clear any pending show
    if (this.showTimeout) {
      clearTimeout(this.showTimeout)
      this.showTimeout = null
    }

    // Don't hide if not visible
    if (!this.isVisible()) return

    // Ensure minimum display time for meaningful feedback
    const elapsed = Date.now() - (this.displayedAt || 0)
    const remaining = Math.max(0, this.minDisplayValue - elapsed)

    this.hideTimeout = setTimeout(() => {
      this.hideTimeout = null
      this.hide()
    }, remaining)
  }

  show() {
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.remove("d-none")
      // Remove CSS failsafe animation if present
      this.overlayTarget.style.animation = "none"
      this.overlayTarget.classList.add("bonid-loading-visible")
      this.overlayTarget.setAttribute("aria-hidden", "false")
      this.displayedAt = Date.now()

      // Failsafe: never let the overlay stick. A real navigation unloads the page
      // before this fires; if nothing navigates (e.g. a JS-handled submit that
      // slipped through), force-hide it so the UI never gets stuck on "Loading…".
      if (this.failsafeTimeout) clearTimeout(this.failsafeTimeout)
      this.failsafeTimeout = setTimeout(() => this.forceHide(), 10000)
    }
  }

  hide() {
    if (this.failsafeTimeout) {
      clearTimeout(this.failsafeTimeout)
      this.failsafeTimeout = null
    }
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.remove("bonid-loading-visible")
      this.overlayTarget.setAttribute("aria-hidden", "true")
      this.displayedAt = null

      // After fade-out transition completes, add d-none
      setTimeout(() => {
        if (this.hasOverlayTarget &&
            !this.overlayTarget.classList.contains("bonid-loading-visible")) {
          this.overlayTarget.classList.add("d-none")
        }
      }, 250)
    }
  }

  forceHide() {
    if (this.showTimeout) clearTimeout(this.showTimeout)
    if (this.hideTimeout) clearTimeout(this.hideTimeout)
    if (this.errorTimeout) clearTimeout(this.errorTimeout)
    if (this.failsafeTimeout) clearTimeout(this.failsafeTimeout)
    this.showTimeout = null
    this.hideTimeout = null
    this.errorTimeout = null
    this.failsafeTimeout = null
    this.isLoading = false

    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.remove("bonid-loading-visible")
      this.overlayTarget.classList.add("d-none")
      this.overlayTarget.setAttribute("aria-hidden", "true")
      this.displayedAt = null
    }
  }

  isVisible() {
    return this.hasOverlayTarget &&
           this.overlayTarget.classList.contains("bonid-loading-visible")
  }

  // ═══════════════════════════════════════════
  // ERROR DISPLAY
  // ═══════════════════════════════════════════

  showError(message) {
    this.isLoading = false

    if (this.showTimeout) clearTimeout(this.showTimeout)
    if (this.hideTimeout) clearTimeout(this.hideTimeout)
    this.showTimeout = null
    this.hideTimeout = null

    // Ensure overlay is visible
    this.show()

    // Switch to error state
    if (this.hasRingTarget) {
      this.ringTarget.classList.add("d-none")
    }
    if (this.hasTextTarget) {
      this.textTarget.innerHTML =
        `<i class="ri-error-warning-line bonid-loading-error-icon"></i>${this._esc(message)}`
      this.textTarget.classList.add("bonid-loading-error-text")
    }

    // Auto-hide after 2.5 seconds
    this.errorTimeout = setTimeout(() => {
      this.errorTimeout = null
      this.clearError()
      this.hide()
    }, 2500)
  }

  clearError() {
    if (this.hasRingTarget) {
      this.ringTarget.classList.remove("d-none")
    }
    if (this.hasTextTarget) {
      this.textTarget.textContent = "Loading..."
      this.textTarget.classList.remove("bonid-loading-error-text")
    }
  }

  _esc(str) {
    if (!str) return ""
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }
}
