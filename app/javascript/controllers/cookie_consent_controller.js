import { Controller } from "@hotwired/stimulus";

// data-controller="cookie-consent"
export default class extends Controller {
  static targets = ["banner", "analytics", "marketing"];

  connect() {
    const consent = JSON.parse(localStorage.getItem("cookieConsent") || "{}");

    // If consent was already saved → remove the banner instantly (no
    // slide-out animation) and load any approved scripts. Slide-out is
    // only for the user-clicks-a-button case.
    if (consent.functional || consent.analytics || consent.marketing) {
      if (this.hasBannerTarget) this.bannerTarget.remove();
      this.loadScripts(consent);
      return;
    }

    // First-time visit: reveal the banner now that Stimulus has had a
    // chance to confirm no prior consent. The .is-revealed class is
    // what triggers the fade-in transition defined in SCSS.
    if (this.hasBannerTarget) {
      requestAnimationFrame(() => {
        this.bannerTarget.classList.add("is-revealed");
      });
    }
  }

  acceptAll() {
    const consent = {
      functional: true,
      analytics: true,
      marketing: true,
    };
    localStorage.setItem("cookieConsent", JSON.stringify(consent));
    this.hideBanner();
    this.loadScripts(consent);
  }

  rejectNonEssential() {
    const consent = {
      functional: true,
      analytics: false,
      marketing: false,
    };
    localStorage.setItem("cookieConsent", JSON.stringify(consent));
    this.hideBanner();
    this.loadScripts(consent);
  }

  savePreferences() {
    const consent = {
      functional: true, // always true
      analytics: this.hasAnalyticsTarget ? this.analyticsTarget.checked : false,
      marketing: this.hasMarketingTarget ? this.marketingTarget.checked : false,
    };
    localStorage.setItem("cookieConsent", JSON.stringify(consent));
    this.hideBanner();
    this.loadScripts(consent);
  }

  hideBanner() {
    if (this.hasBannerTarget) {
      // 👇 Apply the fade-out class
      this.bannerTarget.classList.add("hidden");

      // Optional: remove it from DOM after fade-out finishes
      setTimeout(() => {
        this.bannerTarget.remove();
      }, 500); // matches CSS transition (0.4s)
    }
  }

  loadScripts(consent) {
    if (consent.analytics) {
      if (!document.querySelector("#ga-script")) {
        const script = document.createElement("script");
        script.id = "ga-script";
        script.src = "https://www.googletagmanager.com/gtag/js?id=YOUR_GA_ID";
        script.async = true;
        document.head.appendChild(script);

        window.dataLayer = window.dataLayer || [];
        function gtag(){ window.dataLayer.push(arguments); }
        gtag("js", new Date());
        gtag("config", "YOUR_GA_ID");
      }
    }

    if (consent.marketing) {
      console.log("✅ Marketing scripts would load here");
    }
  }
}
