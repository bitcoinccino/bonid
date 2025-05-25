// app/javascript/controllers/moderation_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["card", "rejectReason", "rejectionModal"];
  static values = {
    id: String
  }

  connect() {
    if (!window.bonBin) window.bonBin = new Set();
    if (!window.badBin) window.badBin = new Map();
  }

  addToBonBin(event) {
    event.preventDefault();
    const id = this.idValue;
    window.bonBin.add(id);
    this.element.classList.add("border-success", "border-3");
    this.element.classList.remove("border-danger");
  }

  promptBadBin(event) {
    event.preventDefault();
    const modal = document.getElementById("rejectionReasonModal");
    const input = document.getElementById("rejectionReasonInput");
    const submitBtn = document.getElementById("confirmRejectBtn");

    input.value = "";
    submitBtn.dataset.submissionId = this.idValue;

    const bsModal = new bootstrap.Modal(modal);
    bsModal.show();
  }

  confirmBadBin(event) {
    event.preventDefault();
    const id = event.target.dataset.submissionId;
    const reason = document.getElementById("rejectionReasonInput").value.trim();

    if (reason === "") {
      alert("Please provide a rejection reason.");
      return;
    }

    window.badBin.set(id, reason);
    const card = document.querySelector(`[data-moderation-id-value="${id}"]`);
    if (card) {
      card.classList.add("border-danger", "border-3");
      card.classList.remove("border-success");
    }

    const modal = bootstrap.Modal.getInstance(document.getElementById("rejectionReasonModal"));
    modal.hide();
  }

  submitBin(event) {
    const action = event.target.dataset.actionType;
    const url = action === "approve" ? "/admin/identity_submissions/approve_bin" : "/admin/identity_submissions/reject_bin";

    const payload = {
      approved_ids: Array.from(window.bonBin),
      rejected: Array.from(window.badBin.entries()).map(([id, reason]) => ({ id, reason }))
    };

    fetch(url, {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(payload)
    })
      .then((res) => res.ok ? location.reload() : alert("Failed to submit actions."))
      .catch((err) => {
        console.error(err);
        alert("Something went wrong.");
      });
  }
}
