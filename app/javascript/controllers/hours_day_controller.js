// app/javascript/controllers/hours_day_controller.js
//
// One instance per weekday row in the BED/BEK operating-hours editor.
// Mimics Google Business Profile's hours UX:
//
//   - The day starts "Closed" (toggle off, slot inputs hidden + disabled
//     so they don't submit).
//   - Flipping the toggle on reveals the first time-slot row and the
//     "Ajoute orè" button.
//   - "Ajoute orè" clones a hidden <template> to add another slot
//     (e.g. lunch break: 08:00–12:00, 13:00–16:00).
//   - Removing the last slot flips the day back to closed.
//
// Inputs in a hidden/closed day are .disabled so the form never submits
// stale times for a day the admin marked closed. The model normalizer
// (ElectoralOffice#normalize_operating_hours) is the second line of
// defense — it drops any half-filled slot.
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["toggle", "slots", "slot", "template", "addBtn"];

  connect() {
    this._sync();
  }

  toggle() {
    if (this.toggleTarget.checked && this.slotTargets.length === 0) {
      // First time the user opens the day — give them an empty slot to fill.
      this._appendSlot();
    }
    this._sync();
  }

  addSlot(event) {
    if (event) event.preventDefault();
    this._appendSlot();
    this._sync();
  }

  removeSlot(event) {
    event.preventDefault();
    const slot = event.currentTarget.closest("[data-hours-day-target='slot']");
    if (!slot) return;
    slot.remove();

    // No slots left → flip the day to closed.
    if (this.slotTargets.length === 0) {
      this.toggleTarget.checked = false;
    }
    this._sync();
  }

  // === private ===

  _appendSlot() {
    // <template> contents need .innerHTML cloning; .content.cloneNode also
    // works but innerHTML is simpler and lets us swap the index sentinel.
    const stamp = `${Date.now()}${Math.floor(Math.random() * 1000)}`;
    const html = this.templateTarget.innerHTML.replace(/__INDEX__/g, stamp);
    this.slotsTarget.insertAdjacentHTML("beforeend", html);
  }

  _sync() {
    const open = this.toggleTarget.checked;
    this.slotsTarget.classList.toggle("d-none", !open);
    if (this.hasAddBtnTarget) this.addBtnTarget.classList.toggle("d-none", !open);

    // Disable inputs in a closed day so they don't submit.
    this.element
      .querySelectorAll("[data-hours-day-target='slot'] input")
      .forEach((el) => { el.disabled = !open; });
  }
}
