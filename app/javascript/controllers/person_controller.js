import { Controller } from "@hotwired/stimulus"

// Person Involvement Controller - BonID-only mode
// All persons must be verified via BonID lookup
export default class extends Controller {
  static targets = [
    "list", "template", "bonid", "preview", "previewWrapper", "status",
    "idTypeSelect", "statusWrapper", "clearWrapper", "removeButton",
    "bonidFields", "bonidInput",
    "feedback", "feedbackMessage", "searchButton", "nameField", "userId",
    "statusField", "priorRecordAlert", "emergencyAlertField", "emergencyCheckbox",
    "photoPreview", "photoImage", "photoPlaceholder",
    "verifiedCard", "nameDisplay", "bonidDisplay", "searchSection"
  ]

  connect() {
    console.log("👮‍♂️ PersonInvolvedController connected (BonID-only mode)")
  }

  toggleStatusField(event) {
    const role = event.target.value
    if (this.hasStatusFieldTarget) {
      if (role === "suspect" || role === "accomplice") {
        this.statusFieldTarget.style.display = ""
      } else {
        this.statusFieldTarget.style.display = "none"
        // Clear status when hiding
        const select = this.statusFieldTarget.querySelector("select")
        if (select) select.value = ""
      }
    }
  }

  toggleEmergencyAlert(event) {
    const role = event.target.value
    if (this.hasEmergencyAlertFieldTarget) {
      if (role === "victim" || role === "witness") {
        this.emergencyAlertFieldTarget.style.display = ""
        // Auto-check for victims
        if (this.hasEmergencyCheckboxTarget && role === "victim") {
          this.emergencyCheckboxTarget.checked = true
        }
      } else {
        this.emergencyAlertFieldTarget.style.display = "none"
        // Uncheck when hiding
        if (this.hasEmergencyCheckboxTarget) {
          this.emergencyCheckboxTarget.checked = false
        }
      }
    }
  }

  addPerson() {
    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, new Date().getTime())
    this.listTarget.insertAdjacentHTML("beforeend", content)
  }

  remove(event) {
    const wrapper = event.target.closest(".nested-fields")
    if (wrapper.querySelector("input[name*='_destroy']")) {
      wrapper.querySelector("input[name*='_destroy']").value = 1
    }
    wrapper.style.display = "none"
  }

  toggleRole(event) {
    const role = event.target.value
    const wrapper = event.target.closest(".nested-fields")
    const statusWrapper = wrapper.querySelector("[data-person-target='statusWrapper']")
    const lockField = wrapper.querySelector("input[name*='locked_primary']")
    const bonidField = wrapper.querySelector("input[name*='bonid']")

    if (statusWrapper) {
      statusWrapper.style.display = role === "suspect" ? "block" : "none"
    }

    if (lockField && bonidField) {
      lockField.value = (role === "suspect" && bonidField.readOnly) ? "true" : "false"
    }
  }

  // === BonID Search Methods ===

  searchBonid(event) {
    event.preventDefault()

    if (!this.hasBonidInputTarget) {
      console.warn("BonID input target not found")
      return
    }

    const bonid = this.bonidInputTarget.value.trim()

    if (!bonid) {
      this.showError("Please enter a BonID")
      return
    }

    // Show loading state
    const button = this.hasSearchButtonTarget ? this.searchButtonTarget : event.currentTarget
    const originalHTML = button.innerHTML
    button.disabled = true
    button.innerHTML = '<i class="ri-loader-4-line" style="animation: spin 1s linear infinite;"></i>'

    this.hideFeedback()

    fetch(`/officers/person_involvements/fetch_identity.json?bonid=${encodeURIComponent(bonid)}`)
      .then(res => res.json())
      .then(data => {
        if (data.success) {
          // populateFromLookup returns false if duplicate detected
          const wasPopulated = this.populateFromLookup(data)

          // Only show success message if person was actually added (not a duplicate)
          if (wasPopulated) {
            // Show ALL prior records alert if exists
            if (data.has_prior_records && data.prior_records_count > 0) {
              this.showPriorRecordsAlert(data)
            } else {
              this.showSuccess("BonID verified successfully")
            }
          }
        } else {
          // Show helpful error with example format
          const isShortCode = bonid.replace(/-/g, "").match(/^\d{6,7}$/)
          const errorMsg = data.error || "BonID not found"
          const hint = isShortCode
            ? " Try the full BonID or verify the digits."
            : " You can also enter just the last 6-7 digits (e.g., 8697761)."
          this.showError(errorMsg + hint)
        }
      })
      .catch(err => {
        console.error("BonID lookup failed:", err)
        this.showError("Lookup failed. Please check connection and try again.")
      })
      .finally(() => {
        button.disabled = false
        button.innerHTML = originalHTML
      })
  }

  populateFromLookup(data) {
    const wrapper = this.element

    // Check for duplicate persons already in this report
    const personId = data.is_tourist
      ? `visitor-${data.visitor_submission_id}`
      : `user-${data.user_id}`

    const existingIds = this.getExistingPersonIds()
    const existingBonids = this.getExistingBonids()

    // Check both by ID and by BonID to catch duplicates
    if (existingIds.includes(personId) || existingBonids.includes(data.bonid)) {
      const fullName = [data.first_name, data.middle_name, data.last_name].filter(n => n).join(" ")
      this.showError(`${fullName} is already involved in this incident report`)
      return false // Indicate duplicate was found
    }

    // Handle tourist (BonTouris) vs citizen (BonID) data
    if (data.is_tourist) {
      this.populateTouristData(data, wrapper)
    } else {
      this.populateCitizenData(data, wrapper)
    }

    // Build full name
    const fullName = [data.first_name, data.middle_name, data.last_name]
      .filter(n => n)
      .join(" ")

    // Populate hidden name field
    if (this.hasNameFieldTarget) {
      this.nameFieldTarget.value = fullName
    } else {
      const nameField = wrapper.querySelector("input[name*='[name]']")
      if (nameField) {
        nameField.value = fullName
      }
    }

    // Set the verified BonID value in hidden field
    if (data.bonid) {
      const bonidHidden = wrapper.querySelector("input[name*='bonid'][type='hidden']")
      if (bonidHidden) bonidHidden.value = data.bonid
    }

    // Show the verified card with photo and name
    this.showVerifiedCard(data, fullName)

    // Hide the search section (keep the input for form submission)
    if (this.hasSearchSectionTarget) {
      this.searchSectionTarget.style.display = "none"
    }

    // Display the person's photo
    this.displayPhoto(data.photo_url)

    return true // Indicate success
  }

  showVerifiedCard(data, fullName) {
    // Show the verified card (use Bootstrap classes to override d-none)
    if (this.hasVerifiedCardTarget) {
      this.verifiedCardTarget.classList.remove("d-none")
      this.verifiedCardTarget.classList.add("d-flex")
    }

    // Set the name display
    if (this.hasNameDisplayTarget) {
      this.nameDisplayTarget.textContent = fullName
    }

    // Set the BonID display
    if (this.hasBonidDisplayTarget) {
      this.bonidDisplayTarget.textContent = data.bonid
    }
  }

  displayPhoto(photoUrl) {
    if (photoUrl) {
      // Show photo preview with actual image
      if (this.hasPhotoImageTarget) {
        this.photoImageTarget.src = photoUrl
      }
      if (this.hasPhotoPreviewTarget) {
        this.photoPreviewTarget.style.display = ""
      }
      if (this.hasPhotoPlaceholderTarget) {
        this.photoPlaceholderTarget.style.display = "none"
      }
    } else {
      // Show placeholder when no photo
      if (this.hasPhotoPreviewTarget) {
        this.photoPreviewTarget.style.display = "none"
      }
      if (this.hasPhotoPlaceholderTarget) {
        this.photoPlaceholderTarget.style.display = ""
      }
    }
  }

  populateCitizenData(data, wrapper) {
    // Populate hidden user_id
    if (this.hasUserIdTarget) {
      this.userIdTarget.value = data.user_id || ""
    } else {
      const userIdField = wrapper.querySelector("input[name*='user_id']")
      if (userIdField) userIdField.value = data.user_id || ""
    }

    // Set additional citizen fields if present
    this.setFieldValue(wrapper, "first_name", data.first_name)
    this.setFieldValue(wrapper, "middle_name", data.middle_name)
    this.setFieldValue(wrapper, "last_name", data.last_name)
    this.setFieldValue(wrapper, "nationality", data.nationality)
  }

  populateTouristData(data, wrapper) {
    // Populate visitor_submission_id for tourists
    const visitorField = wrapper.querySelector("input[name*='visitor_submission_id']")
    if (visitorField) {
      visitorField.value = data.visitor_submission_id || ""
    }

    // Set tourist-specific fields
    this.setFieldValue(wrapper, "first_name", data.first_name)
    this.setFieldValue(wrapper, "middle_name", data.middle_name)
    this.setFieldValue(wrapper, "last_name", data.last_name)
    this.setFieldValue(wrapper, "nationality", data.nationality)
    this.setFieldValue(wrapper, "passport_number", data.passport_number)
    this.setFieldValue(wrapper, "sex", data.sex)

    // Show overstay warning if applicable
    if (data.is_overstay) {
      this.showOverstayAlert(data)
    }
  }

  showOverstayAlert(data) {
    if (this.hasFeedbackTarget && this.hasFeedbackMessageTarget) {
      this.feedbackTarget.style.display = ""
      this.feedbackMessageTarget.innerHTML = `
        <div class="alert alert-danger py-2 px-3 mb-0">
          <div class="d-flex align-items-start gap-2">
            <i class="ri-error-warning-line fs-4"></i>
            <div>
              <strong>⚠️ OVERSTAY ALERT:</strong> This tourist has overstayed by ${data.overstay_days} day(s).
              <div class="mt-1">
                <small>
                  <strong>Visa Expired:</strong> ${data.expires_at ? new Date(data.expires_at).toLocaleDateString() : 'Unknown'}
                </small>
              </div>
            </div>
          </div>
        </div>
      `
    }
  }

  setFieldValue(wrapper, fieldName, value) {
    const field = wrapper.querySelector(`input[name*='${fieldName}']`)
    if (field && value) field.value = value
  }

  setSelectValue(wrapper, fieldName, value) {
    const field = wrapper.querySelector(`select[name*='${fieldName}']`)
    if (field && value) field.value = value
  }

  showError(message) {
    if (this.hasFeedbackTarget && this.hasFeedbackMessageTarget) {
      this.feedbackTarget.style.display = ""
      this.feedbackMessageTarget.innerHTML = `<span class="text-danger"><i class="ri-error-warning-line me-1"></i>${message}</span>`
    }
  }

  showSuccess(message) {
    if (this.hasFeedbackTarget && this.hasFeedbackMessageTarget) {
      this.feedbackTarget.style.display = ""
      this.feedbackMessageTarget.innerHTML = `<span class="text-success"><i class="ri-checkbox-circle-line me-1"></i>${message}</span>`
    }
  }

  // Display ALL prior crime records (not just one)
  showPriorRecordsAlert(data) {
    const records = data.prior_records || []
    const count = data.prior_records_count || records.length

    if (records.length === 0) return

    if (this.hasFeedbackTarget && this.hasFeedbackMessageTarget) {
      this.feedbackTarget.style.display = ""

      // Build HTML for all records
      const recordsHTML = records.map((record, index) => {
        const dateStr = record.incident_date
          ? new Date(record.incident_date).toLocaleDateString()
          : "Unknown date"
        const sevClass = record.severity_level >= 4 ? "danger"
          : record.severity_level >= 3 ? "warning" : "info"
        const statusClass = this.getPriorStatusClass(record.status_display)

        return `
          <div class="border-bottom pb-2 mb-2 ${index === records.length - 1 ? 'border-0 pb-0 mb-0' : ''}">
            <div class="d-flex justify-content-between align-items-start">
              <strong>#${index + 1} ${record.crime_type || "Unknown Crime"}</strong>
              <span class="badge bg-${sevClass}">Lvl ${record.severity_level || '?'}</span>
            </div>
            <small class="text-muted">
              <i class="ri-user-3-line me-1"></i>${record.role_display || 'Suspect'}
              <span class="mx-1">•</span>
              <span class="badge bg-${statusClass}">${record.status_display || 'Unknown'}</span>
              <span class="mx-1">•</span>
              <i class="ri-calendar-line me-1"></i>${dateStr}
            </small>
          </div>
        `
      }).join('')

      this.feedbackMessageTarget.innerHTML = `
        <div class="alert alert-danger py-2 px-3 mb-0">
          <div class="d-flex align-items-start gap-2">
            <i class="ri-alarm-warning-line fs-3 text-danger"></i>
            <div class="flex-grow-1">
              <strong class="text-danger">⚠️ ${count} PRIOR CRIMINAL RECORD${count > 1 ? 'S' : ''} FOUND</strong>
              <div class="mt-2 small">
                ${recordsHTML}
              </div>
            </div>
          </div>
        </div>
      `
    }

    // Also show summary in the prior record alert target
    if (this.hasPriorRecordAlertTarget) {
      this.priorRecordAlertTarget.innerHTML = `
        <div class="alert alert-danger py-2 mb-2">
          <i class="ri-alarm-warning-line me-1"></i>
          <strong>⚠️ ${count} Prior Criminal Record${count > 1 ? 's' : ''}</strong>
        </div>
      `
      this.priorRecordAlertTarget.style.display = ""
    }
  }

  getPriorStatusClass(status) {
    if (!status) return "secondary"
    const lowerStatus = status.toLowerCase()
    // High-risk statuses
    if (["wanted", "fugitive", "armed", "dangerous", "escaped custody"].some(s => lowerStatus.includes(s))) {
      return "danger"
    }
    // Medium-risk
    if (["in custody", "under investigation", "mentally unstable", "detained"].some(s => lowerStatus.includes(s))) {
      return "warning"
    }
    // Resolved
    if (["convicted", "acquitted", "exonerated", "released"].some(s => lowerStatus.includes(s))) {
      return "info"
    }
    return "secondary"
  }

  getPriorStatusAlertClass(status) {
    // High-risk statuses get danger alert
    const dangerStatuses = ["wanted", "fugitive", "armed", "dangerous", "escaped_custody"]
    if (dangerStatuses.some(s => status?.toLowerCase()?.includes(s.replace("_", " ")))) {
      return "alert-danger"
    }
    // Medium-risk statuses get warning
    const warningStatuses = ["in_custody", "under_investigation", "mentally_unstable"]
    if (warningStatuses.some(s => status?.toLowerCase()?.includes(s.replace("_", " ")))) {
      return "alert-warning"
    }
    // Others get info
    return "alert-info"
  }

  hideFeedback() {
    if (this.hasFeedbackTarget) {
      this.feedbackTarget.style.display = "none"
    }
  }

  // Get all existing person IDs in the form to prevent duplicates
  // Excludes the current wrapper (this.element) to avoid false positives
  getExistingPersonIds() {
    const ids = []
    const currentWrapper = this.element

    // Get citizen user_ids (excluding empty, destroyed, and current wrapper)
    document.querySelectorAll('input[name*="[user_id]"]').forEach(input => {
      const wrapper = input.closest('.nested-fields')
      if (wrapper === currentWrapper) return

      const destroyField = wrapper?.querySelector('input[name*="_destroy"]')
      const isDestroyed = destroyField?.value === "1" || destroyField?.value === "true"
      if (input.value && !isDestroyed) {
        ids.push(`user-${input.value}`)
      }
    })
    // Get tourist visitor_submission_ids (excluding empty, destroyed, and current wrapper)
    document.querySelectorAll('input[name*="[visitor_submission_id]"]').forEach(input => {
      const wrapper = input.closest('.nested-fields')
      // Skip the current wrapper we're searching in
      if (wrapper === currentWrapper) return

      const destroyField = wrapper?.querySelector('input[name*="_destroy"]')
      const isDestroyed = destroyField?.value === "1" || destroyField?.value === "true"
      if (input.value && !isDestroyed) {
        ids.push(`visitor-${input.value}`)
      }
    })

    return ids
  }

  // Get all existing BonIDs in the form to prevent duplicates
  // This is a backup check in case user_id comparison fails
  getExistingBonids() {
    const bonids = []
    const currentWrapper = this.element

    document.querySelectorAll('input[name*="[bonid]"]').forEach(input => {
      const wrapper = input.closest('.nested-fields')
      if (wrapper === currentWrapper) return

      const destroyField = wrapper?.querySelector('input[name*="_destroy"]')
      const isDestroyed = destroyField?.value === "1" || destroyField?.value === "true"
      if (input.value && !isDestroyed) {
        bonids.push(input.value)
      }
    })

    return bonids
  }
}
