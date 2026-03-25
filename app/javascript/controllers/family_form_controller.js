import { Controller } from "@hotwired/stimulus"

// Family Form Controller
// Handles: BonID auto-fill, alive/deceased toggle, department→commune cascade
export default class extends Controller {
  static values = { userBonid: String }

  connect() {
    console.info("✅ family-form controller connected, userBonid:", this.userBonidValue)
  }

  // ── BonID Auto-Lookup & Auto-Fill ──────────────────────
  // Fires on input (as user types) with debounce, and on blur
  // Accepts full BonID or last 6 chars (suffix like P2334-4EC or 23344EC)
  async lookupBonid(event) {
    const input = event.currentTarget
    const raw = input.value.trim().toUpperCase().replace(/-/g, "")
    const section = input.closest(".family-section")
    if (!section) return

    const badge = section.querySelector("[data-role='verify-badge']")
    const firstName = section.querySelector("[data-field='first_name']")
    const lastName = section.querySelector("[data-field='last_name']")

    // Need at least 6 chars
    if (raw.length < 6) {
      if (badge) badge.classList.add("d-none")
      return
    }

    // Use last 6 characters as the lookup suffix
    const bonid = raw.slice(-6)

    // Block self-reference
    if (this.hasUserBonidValue) {
      const ownSuffix = this.userBonidValue.replace(/-/g, "").toUpperCase().slice(-6)
      if (bonid === ownSuffix) {
        if (badge) {
          badge.innerHTML = '<span class="text-danger small"><i class="ri-error-warning-line me-1"></i>Ou pa ka ajoute tèt ou kòm fanmi.</span>'
          badge.classList.remove("d-none")
        }
        return
      }
    }

    // Debounce: cancel previous timer
    if (this._lookupTimer) clearTimeout(this._lookupTimer)

    // On blur → immediate. On input → 500ms delay
    const delay = event.type === "blur" ? 0 : 500
    this._lookupTimer = setTimeout(() => this._doLookup(bonid, section, badge, firstName, lastName), delay)
  }

  async _doLookup(bonid, section, badge, firstName, lastName) {
    // Show spinner
    if (badge) {
      badge.innerHTML = '<span class="text-muted small"><i class="ri-loader-4-line ri-spin me-1"></i>Ap chèche...</span>'
      badge.classList.remove("d-none")
    }

    try {
      const response = await fetch(`/emergency_contacts/fetch_from_bonid?bonid=${encodeURIComponent(bonid)}`)
      const data = await response.json()

      if (response.ok && data.success) {
        // Check sex matches relationship (mother=female, father=male)
        const relationship = section.querySelector("input[name*='[relationship]']")?.value
        const sex = (data.sex || "").toLowerCase()
        const isMale = sex === "m" || sex === "male"
        const isFemale = sex === "f" || sex === "female"
        if (relationship === "mother" && isMale) {
          if (badge) {
            badge.innerHTML = '<span class="text-danger small"><i class="ri-error-warning-line me-1"></i>' + data.name + ' se gason. Ou pa ka mete li kòm Manman.</span>'
            badge.classList.remove("d-none")
          }
          return
        }
        if (relationship === "father" && isFemale) {
          if (badge) {
            badge.innerHTML = '<span class="text-danger small"><i class="ri-error-warning-line me-1"></i>' + data.name + ' se fi. Ou pa ka mete li kòm Papa.</span>'
            badge.classList.remove("d-none")
          }
          return
        }

        // Auto-fill name fields
        const nameParts = (data.name || "").split(" ")
        if (firstName && nameParts.length > 0) {
          firstName.value = nameParts[0]
          firstName.classList.add("border-success", "bg-success-subtle")
          setTimeout(() => firstName.classList.remove("border-success", "bg-success-subtle"), 2000)
        }
        if (lastName && nameParts.length > 1) {
          lastName.value = nameParts.slice(1).join(" ")
          lastName.classList.add("border-success", "bg-success-subtle")
          setTimeout(() => lastName.classList.remove("border-success", "bg-success-subtle"), 2000)
        }

        // Show verified badge with photo + remix icon
        if (badge) {
          const photoHtml = data.photo_url
            ? `<img src="${data.photo_url}" class="rounded-circle me-1" width="20" height="20" style="object-fit:cover;width:20px;height:20px;">`
            : ''
          badge.innerHTML = `<span class="text-success small">${photoHtml}<i class="ri-shield-check-fill me-1"></i>${data.name} — Verifye</span>`
        }
      } else if (response.status === 403) {
        if (badge) {
          badge.innerHTML = '<span class="text-danger small"><i class="ri-error-warning-line me-1"></i>Ou pa ka ajoute tèt ou kòm fanmi.</span>'
        }
      } else {
        if (badge) {
          badge.innerHTML = '<span class="text-danger small"><i class="ri-close-circle-line me-1"></i>BonID pa jwenn. Antre non manyèlman.</span>'
        }
      }
    } catch (e) {
      if (badge) {
        badge.innerHTML = '<span class="text-muted small"><i class="ri-wifi-off-line me-1"></i>Pa ka verifye kounye a</span>'
      }
    }
  }

  // ── Alive/Deceased Toggle ──────────────────────────────
  // Hides BonID field and shows death date when "Non" selected
  toggleAlive(event) {
    const section = event.currentTarget.closest(".family-section")
    if (!section) return
    const isAlive = event.currentTarget.value === "true"

    // Hide/show BonID input
    const bonidSection = section.querySelector("[data-alive='bonid']")
    if (bonidSection) bonidSection.classList.toggle("d-none", !isAlive)

    // Hide/show death date
    const deathSection = section.querySelector("[data-alive='death']")
    if (deathSection) deathSection.classList.toggle("d-none", isAlive)
  }

  // ── Department → Commune Cascade ───────────────────────
  async filterCommunes(event) {
    const deptId = event.currentTarget.value
    const section = event.currentTarget.closest(".family-section")
    const communeSelect = section?.querySelector("[data-field='commune']")

    if (!communeSelect) return
    if (!deptId) {
      communeSelect.innerHTML = '<option value="">Chwazi komin</option>'
      return
    }

    communeSelect.innerHTML = '<option value="">Ap chaje...</option>'

    try {
      const response = await fetch(`/communes?department_id=${deptId}`, {
        headers: { "Accept": "application/json" }
      })
      const communes = await response.json()

      communeSelect.innerHTML = '<option value="">Chwazi komin</option>'
      communes.forEach(c => {
        const opt = document.createElement("option")
        opt.value = c.id
        opt.textContent = c.name
        communeSelect.appendChild(opt)
      })
    } catch (e) {
      communeSelect.innerHTML = '<option value="">Erè — eseye ankò</option>'
    }
  }
}
