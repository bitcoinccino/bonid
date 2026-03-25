import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "bonid",
    "name",
    "phone",
    "email",
    "relationship",
    "verified",
    "userId",
    "status",
    "manual",
    "confirmation"
  ]

  connect() {
    this.unlockFields()
  }

  lookup() {
    const bonid = this.bonidTarget.value.trim()

    // If BonID cleared → full reset
    if (bonid.length === 0) {
      this.reset()
      return
    }

    if (bonid.length < 6) return

    fetch(`/api/v1/public/bonid_lookup?bonid=${encodeURIComponent(bonid)}`, {
      headers: { Accept: "application/json" }
    })
      .then(r => r.ok ? r.json() : null)
      .then(data => {
        if (!data || !data.verified) {
          this.showInvalid()
          return
        }

        // ✅ STATUS
        this.statusTarget.textContent =
          "✓ BonID verified — contact locked (except relationship)"
        this.statusTarget.className =
          "fw-semibold text-success mt-1 d-block"

        // ✅ AUTOFILL
        this.nameTarget.value  = data.name  || ""
        this.phoneTarget.value = data.phone || ""
        this.emailTarget.value = data.email || ""

        // ✅ LINK VERIFIED CONTACT TO USER (THIS WAS THE MISSING PART)
        this.userIdTarget.value = data.user_id

        // ✅ LOCK AUTO-FILLED FIELDS
        this.lockFields()

        // ✅ RELATIONSHIP REMAINS EDITABLE
        this.relationshipTarget.removeAttribute("disabled")

        // ✅ VERIFIED FLAG
        this.verifiedTarget.value = "true"

        // ✅ SHOW CONFIRMATION LINE IF PRESENT
        if (this.hasConfirmationTarget) {
          this.confirmationTarget.classList.remove("d-none")
        }

        this.manualTarget.classList.remove("d-none")
      })
      .catch(() => this.showInvalid())
  }

  // ───────────────────────── helpers ─────────────────────────

  lockFields() {
    this.nameTarget.setAttribute("readonly", true)
    this.phoneTarget.setAttribute("readonly", true)
    this.emailTarget.setAttribute("readonly", true)

    this.nameTarget.classList.add("bg-light")
    this.phoneTarget.classList.add("bg-light")
    this.emailTarget.classList.add("bg-light")
  }

  unlockFields() {
    this.nameTarget.removeAttribute("readonly")
    this.phoneTarget.removeAttribute("readonly")
    this.emailTarget.removeAttribute("readonly")

    this.nameTarget.classList.remove("bg-light")
    this.phoneTarget.classList.remove("bg-light")
    this.emailTarget.classList.remove("bg-light")
  }

  showInvalid() {
    this.statusTarget.textContent =
      "✕ BonID not found — enter details manually"
    this.statusTarget.className =
      "fw-semibold text-danger mt-1 d-block"

    this.unlockFields()
    this.manualTarget.classList.remove("d-none")
    this.verifiedTarget.value = "false"
    this.userIdTarget.value = ""
  }

  reset() {
    this.statusTarget.classList.add("d-none")
    this.statusTarget.textContent = ""

    this.unlockFields()

    this.nameTarget.value  = ""
    this.phoneTarget.value = ""
    this.emailTarget.value = ""

    this.verifiedTarget.value = "false"
    this.userIdTarget.value = ""

    if (this.hasConfirmationTarget) {
      this.confirmationTarget.classList.add("d-none")
    }
  }
}
