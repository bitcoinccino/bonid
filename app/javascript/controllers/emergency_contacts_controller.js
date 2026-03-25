import { Controller } from "@hotwired/stimulus"

// Handles dynamic add/remove and BonID autofill for emergency contacts
export default class extends Controller {
  static targets = ["contacts", "template", "bonid", "name", "phone", "email", "address", "empty"]
  static values = { userBonid: String }

  connect() {
    this.index = Date.now()
  }

  // ➕ Add new contact form
  add(event) {
    event.preventDefault()
    // Hide "no contacts" message if present
    if (this.hasEmptyTarget) {
      this.emptyTarget.remove()
    }
    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, this.index++)
    this.contactsTarget.insertAdjacentHTML("beforeend", content)
    this.scrollToLast()
  }

  // 🗑 Remove a contact form (soft delete for persisted)
  remove(event) {
    event.preventDefault()
    const wrapper = event.target.closest(".nested-fields")
    if (!wrapper) return

    if (wrapper.dataset.newRecord === "true") {
      wrapper.remove()
    } else {
      const destroyInput = wrapper.querySelector("input[name*='_destroy']")
      if (destroyInput) destroyInput.value = "1"
      wrapper.style.display = "none"
    }
  }

  // 🔍 Fetch BonID details via API
  async fetchBonid(event) {
    const bonidInput = event.target
    const bonid = bonidInput.value.trim().toUpperCase()
    const wrapper = bonidInput.closest(".nested-fields") || this.element

    console.log("🔍 [EmergencyContacts] fetchBonid triggered", { bonid, wrapper: !!wrapper })

    if (!bonid || bonid.length < 6) {
      console.log("⏭️ [EmergencyContacts] Skipping - BonID too short or empty")
      return
    }
    if (!wrapper) {
      console.error("❌ [EmergencyContacts] Could not find wrapper element")
      return
    }

    // 🚫 Prevent self-reference
    if (this.userBonidValue && bonid === this.userBonidValue.toUpperCase()) {
      this.removeFeedback(wrapper)
      this.markInvalid(bonidInput, "You cannot add yourself as an emergency contact.")
      return
    }

    this.removeFeedback(wrapper)
    this.enableFields(wrapper)
    this.showSpinner(bonidInput)

    try {
      console.log("📡 [EmergencyContacts] Fetching BonID data...")
      const response = await fetch(`/emergency_contacts/fetch_from_bonid?bonid=${encodeURIComponent(bonid)}`)
      const data = await response.json()
      console.log("📥 [EmergencyContacts] Response:", { status: response.status, data })
      this.hideSpinner(bonidInput)

      if (!response.ok) {
        if (response.status === 403) {
          this.markInvalid(bonidInput, "You cannot add your own BonID.")
        } else if (response.status === 404) {
          this.markInvalid(bonidInput, "No verified user found for this BonID.")
        } else {
          this.markInvalid(bonidInput, data.error || "Unexpected server error.")
        }
        return
      }

      if (data.success) {
        console.log("✅ [EmergencyContacts] Filling fields with:", data)
        this.fillAndLockFields(wrapper, data)
        this.markSuccess(bonidInput, "✓ Verified contact found")
        this.replaceBonidWithBadge(bonidInput, data.bonid, data.name, data.photo_url)
      } else {
        this.markInvalid(bonidInput, data.error || "BonID not found.")
      }
    } catch (error) {
      console.error("❌ [EmergencyContacts] Fetch BonID failed:", error)
      this.hideSpinner(bonidInput)
      this.markInvalid(bonidInput, "Network error — please retry.")
    }
  }

  // === Core Helpers ===

  fillAndLockFields(wrapper, data) {
    this.setField(wrapper, "name", data.name)
    this.setField(wrapper, "phone", data.phone)
    this.setField(wrapper, "email", data.email)
    this.setField(wrapper, "address", data.address)
    this.disableFields(wrapper)
  }

  replaceBonidWithBadge(bonidInput, bonid, name, photoUrl) {
    const parent = bonidInput.parentElement
    const inputName = bonidInput.name  // Preserve the original input name

    // Build photo HTML - show avatar with photo or default icon
    const photoHtml = photoUrl
      ? `<img src="${photoUrl}" alt="${name}" class="rounded-circle me-2" style="width: 32px; height: 32px; object-fit: cover;">`
      : `<div class="rounded-circle bg-success-subtle text-success me-2 d-flex align-items-center justify-content-center" style="width: 32px; height: 32px;"><i class="ri-user-line"></i></div>`

    parent.innerHTML = `
      <input type="hidden" name="${inputName}" value="${bonid}" />
      <div class="d-flex align-items-center bg-success-subtle border border-success rounded-3 px-3 py-2">
        ${photoHtml}
        <div class="flex-grow-1">
          <div class="fw-semibold text-success">${name}</div>
          <small class="text-muted"><i class="ri-shield-check-line me-1"></i>Verified — ${bonid}</small>
        </div>
        <button type="button"
                class="btn btn-link btn-sm text-danger p-0 ms-2"
                data-action="click->emergency-contacts#resetContact">
          <i class="ri-close-line"></i>
        </button>
      </div>
    `
    parent.dataset.originalBonid = bonid
  }

  resetContact(event) {
    event.preventDefault()
    const wrapper = event.target.closest(".nested-fields")
    if (!wrapper) return

    const bonidContainer = wrapper.querySelector("[data-original-bonid]")?.parentElement || wrapper.querySelector(".col-md-6")
    if (bonidContainer) {
      bonidContainer.innerHTML = `
        <input type="text"
               name="user[emergency_contacts_attributes][][bonid]"
               placeholder="Enter BonID to autofill"
               class="form-control rounded-3"
               data-emergency-contacts-target="bonid"
               data-action="blur->emergency-contacts#fetchBonid">
      `
    }

    this.enableFields(wrapper)
    this.removeFeedback(wrapper)
  }

  disableFields(wrapper) {
    wrapper.querySelectorAll("input, select, textarea").forEach(el => {
      if (!el.name.includes("[bonid]")) {
        el.setAttribute("readonly", true)
        el.classList.add("bg-light", "text-muted")
      }
    })
  }

  enableFields(wrapper) {
    wrapper.querySelectorAll("input[readonly], select[disabled], textarea[readonly]").forEach(el => {
      el.removeAttribute("readonly")
      el.classList.remove("bg-light", "text-muted")
    })
  }

  setField(wrapper, field, value) {
    const input = wrapper.querySelector(`[name*='[${field}]']`)
    if (input && !input.value && value) input.value = value
  }

  // === Feedback & UI ===

  showSpinner(bonidInput) {
    this.hideSpinner(bonidInput)
    const spinner = document.createElement("div")
    spinner.className = "spinner-border spinner-border-sm text-haitian-blue bonid-spinner ms-2"
    spinner.setAttribute("role", "status")
    spinner.innerHTML = `<span class="visually-hidden">Loading...</span>`
    bonidInput.parentElement.appendChild(spinner)
  }

  hideSpinner(bonidInput) {
    const spinner = bonidInput.parentElement.querySelector(".bonid-spinner")
    if (spinner) spinner.remove()
  }

  markInvalid(input, message) {
    input.classList.remove("is-valid")
    input.classList.add("is-invalid")

    const feedback = document.createElement("div")
    feedback.className = "invalid-feedback d-block mt-1"
    feedback.textContent = message
    input.parentElement.appendChild(feedback)
  }

  markSuccess(input, message) {
    input.classList.remove("is-invalid")
    input.classList.add("is-valid")

    const feedback = document.createElement("div")
    feedback.className = "valid-feedback d-block mt-1 text-haitian-blue"
    feedback.textContent = message
    input.parentElement.appendChild(feedback)
  }

  removeFeedback(wrapper) {
    wrapper.querySelectorAll(".invalid-feedback, .valid-feedback").forEach(el => el.remove())
    const input = wrapper.querySelector("[name*='[bonid]']")
    if (input) input.classList.remove("is-invalid", "is-valid")
  }

  scrollToLast() {
    const last = this.contactsTarget.querySelector(".nested-fields:last-child")
    if (last) last.scrollIntoView({ behavior: "smooth", block: "center" })
  }
}
