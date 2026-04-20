import { Controller } from "@hotwired/stimulus"

// Polling-center wizard companion controller.
//
// Sits next to `wizard` controller on the create-form. Owns:
//   1. Domestik / Dyaspora type toggle (Step 1) — flips which panel is
//      shown in Step 2 and which fields are `required` so wizard-validation
//      only blocks the relevant branch.
//   2. Diaspora mission autofill — when the partner-admin picks a country
//      then a mission, we pre-fill the address + contact fields from the
//      static HaitianDiplomaticMissions registry (no HTTP roundtrip).
//   3. Review-summary rendering — listens for wizard's stepChanged event
//      and rebuilds the read-only summary on the final review step.
//
// Mission data is embedded as a `missions` array value on the controller
// element. Shape per entry:
//   { id, name, type, country, street_line1, street_line2, locality,
//     region, postal_code, phone, email }
export default class extends Controller {
  static targets = [
    "typeRadio",          // both Step-1 radio inputs
    "domesticPanel",      // wrapper around the cascade + street fields
    "diasporaPanel",      // wrapper around country/mission/autofill fields
    "countrySelect",      // diaspora country <select>
    "missionSelect",      // diaspora mission <select> (filtered by country)
    "missionPreview",     // small "selected mission" preview block
    "autofillField",      // any input that should be hydrated from a mission
    "countryCodeInput",   // hidden country_code input (auto-set)
    "domesticRequired",   // fields that should be required only in domestic mode
    "diasporaRequired",   // fields that should be required only in diaspora mode
    "reviewSummary"       // dl rendered on the final review step
  ]

  static values = {
    missions:     { type: Array,  default: [] },
    countryNames: { type: Object, default: {} },
    countryFlags: { type: Object, default: {} }
  }

  connect() {
    // Pre-select the right panel if the form is being re-rendered after
    // a validation error or used in edit mode (center_type already set).
    const checked = this.typeRadioTargets.find(r => r.checked)
    if (checked) this._applyType(checked.value)

    // If a mission was already chosen (edit / re-render), hydrate its
    // country dropdown and preview. We don't auto-fill — that would
    // overwrite any partner-admin-edited values.
    if (this.hasMissionSelectTarget && this.missionSelectTarget.value) {
      const mission = this._findMission(this.missionSelectTarget.value)
      if (mission && this.hasCountrySelectTarget) {
        this.countrySelectTarget.value = mission.country
        this._populateMissionsForCountry(mission.country)
        this.missionSelectTarget.value = mission.id
        this._renderMissionPreview(mission)
      }
    }

    // Listen for wizard step changes so we can rebuild the review on
    // entry to the final step. The wizard dispatches stepChanged on the
    // outer form element this controller is also attached to.
    this.element.addEventListener("wizard:stepChanged", this._onStepChange)
  }

  disconnect() {
    this.element.removeEventListener("wizard:stepChanged", this._onStepChange)
  }

  // ── Step 1: type radio change ────────────────────────────────────
  typeChange(event) {
    this._applyType(event.target.value)
  }

  // ── Step 2: country select change ────────────────────────────────
  countryChange() {
    const cc = this.countrySelectTarget.value
    this._populateMissionsForCountry(cc)
    if (this.hasMissionPreviewTarget) this.missionPreviewTarget.innerHTML = ""
    if (this.hasCountryCodeInputTarget) this.countryCodeInputTarget.value = cc
  }

  // ── Step 2: mission select change → autofill ─────────────────────
  missionChange() {
    const id = this.missionSelectTarget.value
    if (!id) {
      if (this.hasMissionPreviewTarget) this.missionPreviewTarget.innerHTML = ""
      return
    }
    const m = this._findMission(id)
    if (!m) return

    this._renderMissionPreview(m)
    this._autofillFromMission(m)
  }

  // ── Internals ────────────────────────────────────────────────────
  _applyType(value) {
    const isDomestic = value === "domestic"

    if (this.hasDomesticPanelTarget) this.domesticPanelTarget.classList.toggle("d-none", !isDomestic)
    if (this.hasDiasporaPanelTarget) this.diasporaPanelTarget.classList.toggle("d-none", isDomestic)

    // Country code mirrors the choice immediately so server-side
    // validation never sees a mismatch.
    if (this.hasCountryCodeInputTarget) {
      if (isDomestic) {
        this.countryCodeInputTarget.value = "HT"
      } else if (this.hasCountrySelectTarget && this.countrySelectTarget.value) {
        this.countryCodeInputTarget.value = this.countrySelectTarget.value
      } else {
        this.countryCodeInputTarget.value = ""
      }
    }

    // Toggle `required` so the wizard's per-step validation only checks
    // fields in the active branch. Fields hidden in the other panel must
    // not block "Kontinye".
    this.domesticRequiredTargets.forEach(f => this._setRequired(f, isDomestic))
    this.diasporaRequiredTargets.forEach(f => this._setRequired(f, !isDomestic))
  }

  _setRequired(field, on) {
    if (on) field.setAttribute("required", "required")
    else    field.removeAttribute("required")
  }

  _populateMissionsForCountry(countryCode) {
    if (!this.hasMissionSelectTarget) return
    const sel = this.missionSelectTarget
    sel.innerHTML = `<option value="">— Chwazi misyon —</option>`

    if (!countryCode) {
      sel.disabled = true
      return
    }
    const list = this.missionsValue.filter(m => m.country === countryCode)
    list.forEach(m => {
      const opt = document.createElement("option")
      opt.value = m.id
      opt.textContent = `${m.name} (${m.id})`
      sel.appendChild(opt)
    })
    sel.disabled = list.length === 0
  }

  _findMission(id) {
    return this.missionsValue.find(m => m.id === id)
  }

  _autofillFromMission(m) {
    this.autofillFieldTargets.forEach(field => {
      const key = field.dataset.autofillKey
      if (!key) return
      // Only fill empty fields so partner-admin edits aren't clobbered
      // when they switch back-and-forth between missions.
      if (field.value && field.value.trim() !== "") return
      const v = m[key]
      if (v != null && v !== "") field.value = v
    })

    if (this.hasCountryCodeInputTarget) this.countryCodeInputTarget.value = m.country
  }

  _renderMissionPreview(m) {
    if (!this.hasMissionPreviewTarget) return
    const flag = this.countryFlagsValue[m.country] || ""
    const country = this.countryNamesValue[m.country] || m.country
    const addr = [m.street_line1, m.street_line2, m.locality, m.region, m.postal_code]
                   .filter(Boolean).join(", ")
    this.missionPreviewTarget.innerHTML = `
      <div class="border rounded p-3 mt-2 bg-light">
        <div class="fw-semibold">${flag} ${m.name} <span class="text-muted small font-monospace">(${m.id})</span></div>
        <div class="small text-muted mt-1">${addr || "Pa gen adrès"}</div>
        <div class="small text-muted">${country}${m.phone ? " · " + m.phone : ""}</div>
      </div>`
  }

  _onStepChange = (event) => {
    if (!this.hasReviewSummaryTarget) return
    // Rebuild summary every time the user lands on the review step.
    // We don't know which step is "review" — we look for it by class.
    const stepEl = event.detail && event.detail.step
    const reviewStep = this.reviewSummaryTarget.closest("[data-wizard-target='step']")
    if (!reviewStep) return
    const reviewIndex = Array.from(this.element.querySelectorAll("[data-wizard-target='step']")).indexOf(reviewStep) + 1
    if (stepEl !== reviewIndex) return
    this._renderReview()
  }

  _renderReview() {
    const f = (name) => {
      const el = this.element.querySelector(`[name="polling_center[${name}]"]`)
      if (!el) return ""
      if (el.tagName === "SELECT") {
        const opt = el.options[el.selectedIndex]
        return opt ? opt.textContent.trim() : ""
      }
      return (el.value || "").trim()
    }
    const radio = (name) => {
      const checked = this.element.querySelector(`[name="polling_center[${name}]"]:checked`)
      return checked ? checked.value : ""
    }

    const isDomestic = radio("center_type") === "domestic"
    const rows = []
    rows.push(["Tip Lokasyon", isDomestic ? "Domestik (Ayiti)" : "Dyaspora"])
    rows.push(["Non Sant Vòt", f("name") || "—"])

    if (isDomestic) {
      rows.push(["Depatman",       f("department_id")        || "—"])
      rows.push(["Arondisman",     f("arrondissement_id")    || "—"])
      rows.push(["Komin",          f("commune_id")           || "—"])
      rows.push(["Seksyon Komunal",f("communal_section_id")  || "—"])
      rows.push(["Adrès",          f("address_line_1")       || "—"])
      rows.push(["Kòd Postal",     f("postal_code")          || "—"])
    } else {
      rows.push(["Misyon",         f("diplomatic_mission_id") || "—"])
      rows.push(["Adrès",          f("address_line_1")        || "—"])
      rows.push(["Vil",            f("city")                  || "—"])
      rows.push(["Kòd Postal",     f("postal_code")           || "—"])
    }

    rows.push(["Telefòn",     f("contact_phone") || "—"])
    rows.push(["Lè Ouvèti",   this._summarizeHours()])
    if (f("notes")) rows.push(["Nòt", f("notes")])

    this.reviewSummaryTarget.innerHTML = rows.map(([k, v]) => `
      <div class="row py-2 border-bottom">
        <div class="col-4 text-muted small">${k}</div>
        <div class="col-8 small">${this._escape(v)}</div>
      </div>`).join("")
  }

  // Walks the operating-hours editor in Step 4 and produces a one-line
  // summary like "Dimanch 06:00-16:00 · lòt jou Fèmen". Mirrors the
  // server-side display_hours method's formatting intent without
  // requiring a roundtrip to the server.
  _summarizeHours() {
    const dayLabels = {
      mon: "Lendi",   tue: "Madi",     wed: "Mèkredi", thu: "Jedi",
      fri: "Vandredi", sat: "Samdi",   sun: "Dimanch"
    }
    const open = []
    Object.keys(dayLabels).forEach(day => {
      const toggle = this.element.querySelector(`#polling-center-hours_${day}_toggle`)
      if (!toggle || !toggle.checked) return
      const opens  = this.element.querySelectorAll(`input[name^="polling_center[operating_hours][${day}]"][name$="[open]"]`)
      const closes = this.element.querySelectorAll(`input[name^="polling_center[operating_hours][${day}]"][name$="[close]"]`)
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
