// app/javascript/controllers/lookup_modal_controller.js
//
// Drives the dashboard's BonID lookup modal for the MANUAL-ENTRY path.
// User types a 6-char BonID into the dashboard's search box and submits;
// we open a small modal that shows progressive status messages, POSTs to
// the bonid_lookups endpoint, then injects the returned result partial.
//
// The camera path is a regular link to the standalone scans page.

import { Controller } from "@hotwired/stimulus";
import * as Turbo from "@hotwired/turbo";

export default class extends Controller {
  static values = { url: String };
  static targets = ["modal", "status", "statusText", "result", "dialog", "content", "header", "floatingClose"];

  connect() {
    if (!this.hasModalTarget) return;
    this._onHidden = this.onHidden.bind(this);
    this.modalTarget.addEventListener("hidden.bs.modal", this._onHidden);

    // Event delegation for result-frame actions (buttons live inside dynamically
    // injected turbo-stream content, so direct binding races with DOM updates).
    if (this.hasResultTarget) {
      this._onResultClick = this._handleResultClick.bind(this);
      this.resultTarget.addEventListener("click", this._onResultClick);
    }
  }

  disconnect() {
    if (this.hasModalTarget) {
      this.modalTarget.removeEventListener("hidden.bs.modal", this._onHidden);
    }
    if (this.hasResultTarget && this._onResultClick) {
      this.resultTarget.removeEventListener("click", this._onResultClick);
    }
  }

  _handleResultClick(e) {
    // Photo enlarge
    const photo = e.target.closest("[data-photo-enlarge]");
    if (photo) {
      this._openPhotoEnlarge({ preventDefault: () => e.preventDefault(), currentTarget: photo });
      return;
    }
    // Confirm / Reject identity
    const confirmBtn = e.target.closest("[data-confirm-url]");
    if (confirmBtn && !confirmBtn.disabled) {
      this._confirmIdentity({ preventDefault: () => e.preventDefault(), currentTarget: confirmBtn });
      return;
    }
    // "New Lookup" / rescan — close modal so dashboard form is ready again
    const rescanBtn = e.target.closest('[data-action*="partner-scanner#rescan"]');
    if (rescanBtn) {
      e.preventDefault();
      const Modal = window.bootstrap?.Modal;
      if (Modal && this.hasModalTarget) {
        Modal.getOrCreateInstance(this.modalTarget).hide();
      }
    }
  }

  onHidden() {
    // Reset modal state for next open
    this.resetUI();
  }

  resetUI() {
    if (this.hasResultTarget) {
      this.resultTarget.innerHTML = "";
      this.resultTarget.classList.add("d-none");
    }
    if (this.hasStatusTarget) this.statusTarget.classList.remove("d-none");
    if (this.hasStatusTextTarget) this.statusTextTarget.textContent = "Searching BonID...";
    // Loading layout: fullscreen + dark gradient + no header + floating close
    if (this.hasDialogTarget) {
      this.dialogTarget.classList.add("modal-fullscreen");
      this.dialogTarget.classList.remove("modal-xl", "modal-dialog-centered", "modal-dialog-scrollable");
    }
    if (this.hasContentTarget) {
      this.contentTarget.style.background =
        "linear-gradient(135deg,#0d132d 0%,#1a2340 50%,#0d132d 100%)";
      this.contentTarget.style.boxShadow = "";
    }
    if (this.hasHeaderTarget) this.headerTarget.classList.add("d-none");
    if (this.hasFloatingCloseTarget) {
      this.floatingCloseTarget.classList.remove("d-none");
      this.floatingCloseTarget.classList.add("btn-close-white");
    }
    // Re-enable static backdrop + disabled ESC during loading (so user can't
    // accidentally cancel mid-lookup); showResult re-enables dismiss.
    if (this.hasModalTarget) {
      this.modalTarget.setAttribute("data-bs-backdrop", "static");
      this.modalTarget.setAttribute("data-bs-keyboard", "false");
    }
  }

  setStatus(text) {
    if (this.hasStatusTextTarget) this.statusTextTarget.textContent = text;
  }

  showResult(html) {
    if (!this.hasResultTarget) return;
    // Swap to centered modal-xl. The result partial brings its own card
    // chrome (green/red/amber header), so make the modal-content transparent
    // and hide our header + floating X — partial is the only visible chrome.
    if (this.hasDialogTarget) {
      this.dialogTarget.classList.remove("modal-fullscreen");
      this.dialogTarget.classList.add("modal-xl", "modal-dialog-centered", "modal-dialog-scrollable");
    }
    if (this.hasContentTarget) {
      this.contentTarget.style.background = "transparent";
      this.contentTarget.style.boxShadow = "none";
    }
    if (this.hasHeaderTarget) this.headerTarget.classList.add("d-none");
    if (this.hasFloatingCloseTarget) this.floatingCloseTarget.classList.add("d-none");
    // Re-enable backdrop / ESC dismiss now that there's no visible close button
    if (this.hasModalTarget) {
      this.modalTarget.removeAttribute("data-bs-backdrop");
      this.modalTarget.removeAttribute("data-bs-keyboard");
    }
    // Hide spinner, reveal result frame, then render the turbo-stream
    // (which targets `scan_result_frame` — id of the result target).
    this.statusTarget?.classList.add("d-none");
    this.resultTarget.classList.remove("d-none");
    Turbo.renderStreamMessage(html);
    // Action handlers (photo enlarge, confirm/reject, rescan) are wired via
    // event delegation on resultTarget (see _handleResultClick) — no per-render
    // binding needed.
  }

  _openPhotoEnlarge(e) {
    e.preventDefault();
    const photo = e.currentTarget;
    const url = photo.dataset.photoUrl || photo.src;
    const name = photo.dataset.personName || "Person";

    // Bootstrap modal-on-modal is unreliable when the inner modal is nested
    // inside the parent modal-body. Build a lightweight overlay on <body>.
    let overlay = document.getElementById("lookupPhotoOverlay");
    if (!overlay) {
      overlay = document.createElement("div");
      overlay.id = "lookupPhotoOverlay";
      overlay.style.cssText =
        "position:fixed;inset:0;background:rgba(0,0,0,0.92);" +
        "z-index:20000;display:flex;flex-direction:column;align-items:center;" +
        "justify-content:center;padding:2rem;cursor:zoom-out;";
      overlay.innerHTML =
        '<button type="button" aria-label="Close" ' +
        'style="position:absolute;top:1.25rem;right:1.5rem;background:transparent;' +
        'border:0;color:#fff;font-size:2rem;line-height:1;cursor:pointer;">×</button>' +
        '<div style="color:#fff;font-family:var(--font-heading);font-weight:600;' +
        'font-size:1.1rem;margin-bottom:1rem;text-align:center;" ' +
        'data-overlay-name></div>' +
        '<img alt="Enlarged photo" data-overlay-img ' +
        'style="max-width:90vw;max-height:80vh;border-radius:12px;' +
        'box-shadow:0 8px 32px rgba(0,0,0,0.5);">' +
        '<div style="color:rgba(255,255,255,0.6);font-size:.8rem;margin-top:1rem;">' +
        'Click outside or press ESC to close</div>';
      document.body.appendChild(overlay);

      const close = () => {
        overlay.style.display = "none";
        document.removeEventListener("keydown", onKey);
      };
      const onKey = (ev) => { if (ev.key === "Escape") close(); };
      overlay.addEventListener("click", (ev) => {
        if (ev.target === overlay || ev.target.tagName === "BUTTON") close();
      });
      overlay._open = () => {
        overlay.style.display = "flex";
        document.addEventListener("keydown", onKey);
      };
    }

    overlay.querySelector("[data-overlay-img]").src = url;
    overlay.querySelector("[data-overlay-name]").textContent = name;
    overlay._open();
  }

  async _confirmIdentity(e) {
    e.preventDefault();
    const btn = e.currentTarget;
    const url = btn.dataset.confirmUrl;
    const confirmed = btn.dataset.confirmed;
    if (!url) return;

    const originalHtml = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML =
      '<i class="ri-loader-4-line" style="animation:spin 1s linear infinite"></i> Processing...';

    const formData = new FormData();
    formData.append("confirmed", confirmed);
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content;
    if (csrf) formData.append("authenticity_token", csrf);

    try {
      const resp = await fetch(url, {
        method: "POST",
        headers: {
          Accept: "text/vnd.turbo-stream.html",
          "X-CSRF-Token": csrf || ""
        },
        body: formData,
        credentials: "same-origin"
      });
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      const html = await resp.text();
      if (html.includes("turbo-stream")) {
        Turbo.renderStreamMessage(html);
        // Delegated click handler on resultTarget picks up the new buttons —
        // no re-bind needed.
      }
    } catch (err) {
      console.error("[lookup-modal] confirm failed:", err);
      btn.disabled = false;
      btn.innerHTML = originalHtml;
    }
  }

  // ── Manual-entry submit ────────────────────────────────────

  async submitManual(event) {
    event.preventDefault();
    const form = event.currentTarget;
    const input = form.querySelector("input[name='bonid']");
    const bonid = input?.value?.trim().toUpperCase();
    if (!bonid || bonid.length === 0) return;

    // Open the modal with the initial "Searching BonID..." status
    const Modal = window.bootstrap?.Modal;
    if (!Modal) {
      console.error("[lookup-modal] Bootstrap not loaded");
      return;
    }
    this.resetUI();
    Modal.getOrCreateInstance(this.modalTarget).show();

    // POST the lookup (run in parallel with a minimum-display floor so the
    // initial "Searching BonID..." message is always visible long enough)
    const formData = new FormData();
    formData.append("bonid_lookup[bonid]", bonid);
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content;
    if (csrf) formData.append("bonid_lookup[authenticity_token]", csrf);

    const fetchPromise = fetch(this.urlValue, {
      method: "POST",
      headers: {
        Accept: "text/vnd.turbo-stream.html",
        "X-CSRF-Token": csrf || ""
      },
      body: formData,
      credentials: "same-origin"
    });

    try {
      // Hold "Searching BonID..." for at least 2.8s even if network is fast
      const [resp] = await Promise.all([fetchPromise, this._sleep(2800)]);

      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      const html = await resp.text();
      if (!html.includes("turbo-stream")) {
        throw new Error("Unexpected response");
      }

      // Detect failure: invalid partial sets data-result-type="invalid"
      const isInvalid = /data-result-type=["']invalid["']|Verification Failed|Not Found|Pa Jwenn/i.test(html);

      if (isInvalid) {
        // Failure path — short pause then render the error card
        this.setStatus("BonID not found...");
        await this._sleep(2200);
        this.showResult(html);
        return;
      }

      // Success path — progressive messages
      this.setStatus("BonID found...");
      const isEligible = /Eligibility|eligibility|eligible|Voter/i.test(html);
      await this._sleep(2800);
      if (isEligible) {
        this.setStatus("BonID is eligible to vote...");
        await this._sleep(2800);
      }
      this.showResult(html);
    } catch (err) {
      console.error("[lookup-modal] lookup failed:", err);
      this.setStatus(`Error: ${err.message}`);
    }
  }

  _sleep(ms) {
    return new Promise((r) => setTimeout(r, ms));
  }
}
