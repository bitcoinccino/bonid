// ===============================================================
// BonID ESBuild Application Bootstrap (FINAL, STABLE, CORRECT)
// ===============================================================

// ─────────────────────────────────────────
// Turbo (MUST load first)
// ─────────────────────────────────────────
import { Turbo } from "@hotwired/turbo-rails";
Turbo.config.drive.progressBarDelay = 200;

// ─────────────────────────────────────────
// Bootstrap CSS + JS
// ─────────────────────────────────────────
import "bootstrap/dist/css/bootstrap.min.css";
import * as bootstrap from "bootstrap";
window.bootstrap = bootstrap;

// ─────────────────────────────────────────
// Stimulus (NO EXPORTS)
// ─────────────────────────────────────────
import { Application } from "@hotwired/stimulus";
const application = Application.start();
window.Stimulus = application; // debug only

// ─────────────────────────────────────────
// Global Libraries
// ─────────────────────────────────────────
import "leaflet/dist/leaflet.css";
import L from "leaflet";
import { Html5Qrcode } from "html5-qrcode";
import SignaturePad from "signature_pad";
import "chartkick/chart.js";

window.L = L;
window.Html5Qrcode = Html5Qrcode;
window.SignaturePad = SignaturePad;
window.Chartkick ||= Chartkick;

// ─────────────────────────────────────────
// Fix Leaflet Marker Icons (ESBuild)
// ─────────────────────────────────────────
import markerIcon from "leaflet/dist/images/marker-icon.png";
import markerShadow from "leaflet/dist/images/marker-shadow.png";

delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
  iconUrl: markerIcon,
  shadowUrl: markerShadow,
});

// ─────────────────────────────────────────
// Load Stimulus Controllers
// ─────────────────────────────────────────
import "./controllers";

// ─────────────────────────────────────────
// Visual Engines (SIDE-EFFECT ONLY)
// ─────────────────────────────────────────
import "./visual/matrix_mesh";
import "./visual/constellation";

// ─────────────────────────────────────────
// Turbo Confirm — replace browser dialog with styled modal
// ─────────────────────────────────────────
// Intercepts ALL data-turbo-confirm attributes and shows #confirmationModal
// instead of the native window.confirm() browser popup.
Turbo.config.forms.confirm = (message) => {
  return new Promise((resolve) => {
    const modalEl = document.getElementById("confirmationModal");
    if (!modalEl) {
      // Fallback to native if modal not in this layout
      resolve(window.confirm(message));
      return;
    }

    // Inject the confirm message text into the modal body
    const body = modalEl.querySelector("#confirmationModalBody");
    if (body) body.textContent = message;

    // Show the Bootstrap modal
    const modal = bootstrap.Modal.getOrCreateInstance(modalEl);
    modal.show();

    const confirmBtn = modalEl.querySelector("#confirmationModalConfirmBtn");
    const dismissBtns = modalEl.querySelectorAll('[data-bs-dismiss="modal"]');

    const onConfirm = () => {
      cleanup();
      modal.hide();
      resolve(true);
    };

    const onCancel = () => {
      cleanup();
      resolve(false);
    };

    // Also resolve false if modal is closed via backdrop click or ESC
    const onHidden = () => {
      cleanup();
      resolve(false);
    };

    function cleanup() {
      confirmBtn?.removeEventListener("click", onConfirm);
      dismissBtns.forEach((btn) => btn.removeEventListener("click", onCancel));
      modalEl.removeEventListener("hidden.bs.modal", onHidden);
    }

    confirmBtn?.addEventListener("click", onConfirm, { once: true });
    dismissBtns.forEach((btn) => btn.addEventListener("click", onCancel, { once: true }));
    modalEl.addEventListener("hidden.bs.modal", onHidden, { once: true });
  });
};

// ─────────────────────────────────────────
// Global "Processing…" Button State
// ─────────────────────────────────────────
// Automatically disables submit buttons and shows a spinner on ALL Turbo form
// submissions. Prevents double-clicks in low-bandwidth environments (Haiti).
// Skips buttons already managed by a Stimulus form-handler controller.
// Opt out per-button with data-no-processing="true".
;(() => {
  const ATTR_ORIGINAL = "_bonid_original_html"

  document.addEventListener("turbo:submit-start", (event) => {
    const submitter = event.detail?.formSubmission?.submitter
    if (!submitter) return
    if (submitter.dataset.noProcessing === "true") return

    // Skip if a form-handler or qr-refresh Stimulus controller manages this form
    const form = submitter.closest("form")
    if (form?.dataset.controller?.match(/form-handler|qr-refresh/)) return

    // Store original content and disable
    if (submitter.tagName === "INPUT") {
      submitter._bonid_original_value = submitter.value
      submitter.disabled = true
      submitter.value = "Processing\u2026"
    } else {
      submitter[ATTR_ORIGINAL] = submitter.innerHTML
      submitter.disabled = true
      submitter.innerHTML =
        '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Processing\u2026'
    }
  })

  function restoreButton(event) {
    const submitter = event.detail?.formSubmission?.submitter
    if (!submitter) return

    if (submitter.tagName === "INPUT" && submitter._bonid_original_value) {
      submitter.disabled = false
      submitter.value = submitter._bonid_original_value
      delete submitter._bonid_original_value
    } else if (submitter[ATTR_ORIGINAL]) {
      submitter.disabled = false
      submitter.innerHTML = submitter[ATTR_ORIGINAL]
      delete submitter[ATTR_ORIGINAL]
    }
  }

  document.addEventListener("turbo:submit-end", restoreButton)
  document.addEventListener("turbo:fetch-request-error", restoreButton)

  // Fallback for non-Turbo forms (data-turbo="false")
  // Page navigates away on submit, so no restore listener needed.
  document.addEventListener("submit", (event) => {
    const form = event.target
    if (form.dataset.turbo !== "false") return  // only handle non-Turbo forms

    const submitter = event.submitter
    if (!submitter || submitter.dataset.noProcessing === "true") return
    if (form.dataset.controller?.match(/form-handler|qr-refresh/)) return

    if (submitter.tagName === "INPUT") {
      submitter._bonid_original_value = submitter.value
      submitter.disabled = true
      submitter.value = "Processing\u2026"
    } else {
      submitter[ATTR_ORIGINAL] = submitter.innerHTML
      submitter.disabled = true
      submitter.innerHTML =
        '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Processing\u2026'
    }
  })
})()

// ─────────────────────────────────────────
// Bootstrap Re-init (Turbo-safe)
// ─────────────────────────────────────────
function initBootstrap() {
  document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach((el) => {
    if (!bootstrap.Tooltip.getInstance(el)) {
      new bootstrap.Tooltip(el);
    }
  });

  document.querySelectorAll('[data-bs-toggle="dropdown"]').forEach((el) => {
    bootstrap.Dropdown.getOrCreateInstance(el);
  });
}

// ─────────────────────────────────────────
// Clean up stale Bootstrap modal artifacts on Turbo navigation
// ─────────────────────────────────────────
// When Turbo Drive navigates between pages, Bootstrap modals can leave
// behind .modal-backdrop elements, body.modal-open, and overflow:hidden.
// This purges them before Turbo caches the page and after each load.
function cleanupBootstrapModals() {
  // Dispose any lingering Bootstrap Modal instances
  document.querySelectorAll(".modal").forEach((el) => {
    const instance = bootstrap.Modal.getInstance(el);
    if (instance) {
      instance.hide();
      instance.dispose();
    }
  });

  // Remove orphaned backdrop elements
  document.querySelectorAll(".modal-backdrop").forEach((el) => el.remove());

  // Restore body scroll
  document.body.classList.remove("modal-open");
  document.body.style.removeProperty("overflow");
  document.body.style.removeProperty("padding-right");
}

document.addEventListener("turbo:before-cache", cleanupBootstrapModals);

document.addEventListener("turbo:load", () => {
  // Clean up any backdrops that survived the navigation
  document.querySelectorAll(".modal-backdrop").forEach((el) => el.remove());
  document.body.classList.remove("modal-open");
  document.body.style.removeProperty("overflow");
  document.body.style.removeProperty("padding-right");

  initBootstrap();
  Chartkick?.eachChart((chart) => chart.redraw());
});
