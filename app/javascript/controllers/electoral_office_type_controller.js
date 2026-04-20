import { Controller } from "@hotwired/stimulus"

// Electoral-office wizard companion — sits next to `wizard` on the
// BED/BEK create form. Owns:
//   1. Type toggle (Step 1) — flips which address-cascade tier is
//      `required`. BED needs a department; BEK needs a commune.
//   2. Smart name suggestion — when the partner-admin picks a BED with
//      department "Ouest" we pre-fill the name "BED Ouest"; same for
//      BEK + commune. Only fires while the name field is empty so we
//      never clobber an admin-edited value.
//   3. Review-summary rebuild on entry to the final wizard step.
//
// No autofill data table needed — the address controller already owns
// the cascade; we only react to type/scope changes.
export default class extends Controller {
  static targets = [
    "typeRadio",          // both Step-1 radios
    "departmentSelect",   // address[department_id] <select>
    "communeSelect",      // address[commune_id] <select>
    "nameInput",          // electoral_office[name] text input
    "scopeHint",          // small inline hint: "BED → depatman" vs "BEK → komin"
    "reviewSummary"
  ]

  connect() {
    const checked = this.typeRadioTargets.find(r => r.checked)
    if (checked) this._applyType(checked.value)
    this.element.addEventListener("wizard:stepChanged", this._onStepChange)
  }

  disconnect() {
    this.element.removeEventListener("wizard:stepChanged", this._onStepChange)
  }

  // ── Step 1 ───────────────────────────────────────────────────────
  typeChange(event) {
    this._applyType(event.target.value)
  }

  // ── Step 2 (address cascade triggers these) ──────────────────────
  departmentChanged() {
    this._suggestName()
  }

  communeChanged() {
    this._suggestName()
  }

  // ── Internals ────────────────────────────────────────────────────
  _applyType(value) {
    const isBed = value === "bed"

    if (this.hasDepartmentSelectTarget) {
      this._setRequired(this.departmentSelectTarget, true) // both types need it
    }
    if (this.hasCommuneSelectTarget) {
      // BEK requires commune; BED doesn't (the cascade can stop at dept).
      this._setRequired(this.communeSelectTarget, !isBed)
    }
    if (this.hasScopeHintTarget) {
      this.scopeHintTarget.textContent = isBed
        ? "Yon BED kouvri yon depatman antye — w sèlman bezwen chwazi depatman an."
        : "Yon BEK kouvri yon komin sèlman — kontinye jiska komin lan."
    }

    // Re-suggest the name in case the type changed mid-edit.
    this._suggestName()
  }

  _setRequired(field, on) {
    if (on) field.setAttribute("required", "required")
    else    field.removeAttribute("required")
  }

  // Pre-fills the name field with "<TYPE> <ScopeName>" while the field
  // is empty. The admin can always type something else.
  _suggestName() {
    if (!this.hasNameInputTarget) return
    if (this.nameInputTarget.value && this.nameInputTarget.value.trim() !== "") return

    const type = this._currentType()
    if (!type) return

    let scopeName = ""
    if (type === "bed" && this.hasDepartmentSelectTarget) {
      const opt = this.departmentSelectTarget.options[this.departmentSelectTarget.selectedIndex]
      if (opt && opt.value) scopeName = opt.textContent.trim()
    } else if (type === "bek" && this.hasCommuneSelectTarget) {
      const opt = this.communeSelectTarget.options[this.communeSelectTarget.selectedIndex]
      if (opt && opt.value) scopeName = opt.textContent.trim()
    }

    if (scopeName) {
      this.nameInputTarget.value = `${type.toUpperCase()} ${scopeName}`
    }
  }

  _currentType() {
    const checked = this.typeRadioTargets.find(r => r.checked)
    return checked ? checked.value : ""
  }

  _onStepChange = (event) => {
    if (!this.hasReviewSummaryTarget) return
    const reviewStep = this.reviewSummaryTarget.closest("[data-wizard-target='step']")
    if (!reviewStep) return
    const reviewIndex = Array.from(this.element.querySelectorAll("[data-wizard-target='step']")).indexOf(reviewStep) + 1
    if (event.detail.step !== reviewIndex) return
    this._renderReview()
  }

  _renderReview() {
    const f = (name) => {
      const el = this.element.querySelector(`[name="electoral_office[${name}]"]`)
      if (!el) return ""
      if (el.tagName === "SELECT") {
        const opt = el.options[el.selectedIndex]
        return opt ? opt.textContent.trim() : ""
      }
      return (el.value || "").trim()
    }
    const addr = (name) => {
      const el = this.element.querySelector(`[name="electoral_office[address_attributes][${name}]"]`)
      if (!el) return ""
      if (el.tagName === "SELECT") {
        const opt = el.options[el.selectedIndex]
        return opt ? opt.textContent.trim() : ""
      }
      return (el.value || "").trim()
    }

    const type = this._currentType()
    const isBed = type === "bed"

    const rows = []
    rows.push(["Tip Biwo",     isBed ? "BED (Departmental)" : "BEK (Komunal)"])
    rows.push(["Non Biwo",     f("name") || "—"])
    rows.push(["Depatman",     addr("department_id") || "—"])
    if (!isBed) {
      rows.push(["Arondisman",     addr("arrondissement_id") || "—"])
      rows.push(["Komin",          addr("commune_id")        || "—"])
      rows.push(["Seksyon Komunal",addr("communal_section_id") || "—"])
    }
    rows.push(["Adrès / Ri",   addr("street_address") || "—"])
    rows.push(["Kòd Postal",   addr("postal_code")    || "—"])
    rows.push(["Telefòn",      f("phone") || "—"])
    rows.push(["Lè Ouvèti",    this._summarizeHours()])
    if (f("notes")) rows.push(["Nòt", f("notes")])

    this.reviewSummaryTarget.innerHTML = rows.map(([k, v]) => `
      <div class="row py-2 border-bottom">
        <div class="col-4 text-muted small">${k}</div>
        <div class="col-8 small">${this._escape(v)}</div>
      </div>`).join("")
  }

  _summarizeHours() {
    const dayLabels = {
      mon: "Lendi",   tue: "Madi",     wed: "Mèkredi", thu: "Jedi",
      fri: "Vandredi", sat: "Samdi",   sun: "Dimanch"
    }
    const open = []
    Object.keys(dayLabels).forEach(day => {
      const toggle = this.element.querySelector(`#office-hours_${day}_toggle`)
      if (!toggle || !toggle.checked) return
      const opens  = this.element.querySelectorAll(`input[name^="electoral_office[operating_hours][${day}]"][name$="[open]"]`)
      const closes = this.element.querySelectorAll(`input[name^="electoral_office[operating_hours][${day}]"][name$="[close]"]`)
      const slots = []
      opens.forEach((openIn, i) => {
        const closeIn = closes[i]
        if (openIn.value && closeIn && closeIn.value) {
          slots.push(`${openIn.value}-${closeIn.value}`)
        }
      })
      if (slots.length) open.push(`${dayLabels[day]} ${slots.join(", ")}`)
    })
    return open.length ? open.join(" · ") : "Pa gen lè defini"
  }

  _escape(s) {
    return String(s).replace(/[&<>"']/g, c => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
    }[c]))
  }
}
