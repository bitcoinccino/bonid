import { Controller } from "@hotwired/stimulus";

// data-controller="cookie-consent" (shared/_cookie_banner)
//
// - First visit: the banner fades in until the visitor chooses.
// - After a choice it stays in the page, hidden, so it can be reopened
//   from any [data-cookie-settings] link (footer, privacy policy) to
//   change or withdraw consent.
// - Analytics loads only with consent AND a configured measurement ID
//   (<meta name="ga-measurement-id">); without one nothing is sent.
// - Choices live in localStorage, which can be unavailable (private
//   mode, blocked storage): the banner then just shows each visit.
const STORAGE_KEY = "cookieConsent";

export default class extends Controller {
  static targets = ["banner", "analytics"];

  connect() {
    this.openFromLink = this.openFromLink.bind(this);
    document.addEventListener("click", this.openFromLink);

    const consent = this.readConsent();
    if (consent) {
      this.loadScripts(consent);
      return; // stays hidden until reopened
    }
    this.reveal();
  }

  disconnect() {
    document.removeEventListener("click", this.openFromLink);
  }

  openFromLink(event) {
    const link = event.target.closest("[data-cookie-settings]");
    if (!link) return;
    event.preventDefault();
    this.open();
  }

  // Reopen with the saved choices ticked.
  open() {
    const consent = this.readConsent() || {};
    if (this.hasAnalyticsTarget) this.analyticsTarget.checked = !!consent.analytics;
    this.reveal();
  }

  // Only consent to what the banner actually offered: without the
  // analytics option (no measurement ID), "accept" means essential only.
  acceptAll() {
    this.save({ functional: true, analytics: this.hasAnalyticsTarget });
  }

  // Also the single "Got it" button of the essential-only notice.
  rejectNonEssential() {
    this.save({ functional: true, analytics: false });
  }

  savePreferences() {
    this.save({
      functional: true, // always on
      analytics: this.hasAnalyticsTarget && this.analyticsTarget.checked,
    });
  }

  // ── internals ────────────────────────────────────────────────

  save(consent) {
    const previous = this.readConsent();
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(consent));
    } catch (_) { /* storage blocked: the choice applies to this page only */ }

    this.hide();

    // A loaded script can't be unloaded: withdrawing analytics after it
    // ran needs a fresh page.
    if (previous?.analytics && !consent.analytics && document.getElementById("ga-script")) {
      window.location.reload();
      return;
    }
    this.loadScripts(consent);
  }

  readConsent() {
    try {
      const consent = JSON.parse(localStorage.getItem(STORAGE_KEY) || "null");
      return consent && consent.functional ? consent : null;
    } catch (_) {
      return null;
    }
  }

  reveal() {
    if (!this.hasBannerTarget) return;
    this.bannerTarget.classList.remove("hidden");
    requestAnimationFrame(() => this.bannerTarget.classList.add("is-revealed"));
  }

  hide() {
    if (!this.hasBannerTarget) return;
    this.bannerTarget.classList.remove("is-revealed");
    this.bannerTarget.classList.add("hidden");
  }

  loadScripts(consent) {
    if (consent.analytics) this.loadAnalytics();
  }

  loadAnalytics() {
    const id = document.querySelector('meta[name="ga-measurement-id"]')?.content;
    if (!id || document.getElementById("ga-script")) return;

    window.dataLayer = window.dataLayer || [];
    window.gtag = window.gtag || function () { window.dataLayer.push(arguments); };
    window.gtag("js", new Date());
    window.gtag("config", id);

    const script = document.createElement("script");
    script.id = "ga-script";
    script.async = true;
    script.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(id)}`;
    document.head.appendChild(script);
  }
}
