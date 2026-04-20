import { Controller } from "@hotwired/stimulus"

// Mission-participation wizard companion. Sits next to `wizard` on the
// per-election diplomatic-mission configure form. Owns:
//   - Review-summary rebuild on entry to the final wizard step.
//
// Mission identity is locked-in by a hidden `diplomatic_mission_id` so
// there's no type toggle / no autofill — just summary rendering.
export default class extends Controller {
  static targets = ["reviewSummary"]
  static values = {
    statusLabels: { type: Object, default: {} },
    missionName:  { type: String, default: "" },
    missionId:    { type: String, default: "" },
    missionType:  { type: String, default: "" },
    missionRegion:{ type: String, default: "" },
    missionCountry:{ type: String, default: "" }
  }

  connect() {
    this.element.addEventListener("wizard:stepChanged", this._onStepChange)
  }

  disconnect() {
    this.element.removeEventListener("wizard:stepChanged", this._onStepChange)
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
      const el = this.element.querySelector(`[name="election_mission_participation[${name}]"]`)
      if (!el) return ""
      if (el.tagName === "SELECT") {
        const opt = el.options[el.selectedIndex]
        return opt ? opt.textContent.trim() : ""
      }
      return (el.value || "").trim()
    }

    const rows = []
    rows.push(["Misyon",      `${this.missionNameValue} (${this.missionIdValue})`])
    rows.push(["Tip / Peyi",  `${this.missionTypeValue} · ${this.missionCountryValue}`])
    rows.push(["Estati",      f("status") || "—"])
    rows.push(["Telefòn",     f("contact_phone") || "—"])
    rows.push(["Imel",        f("contact_email") || "—"])

    const addr = [
      f("street_line1"),
      f("street_line2"),
      [f("locality"), f("region"), f("postal_code")].filter(Boolean).join(" ")
    ].filter(Boolean).join("\n")
    rows.push(["Adrès",       addr || "—"])

    rows.push(["Lè Ouvèti",   this._summarizeHours()])
    if (f("notes")) rows.push(["Nòt", f("notes")])

    this.reviewSummaryTarget.innerHTML = rows.map(([k, v]) => `
      <div class="row py-2 border-bottom">
        <div class="col-4 text-muted small">${k}</div>
        <div class="col-8 small" style="white-space: pre-wrap;">${this._escape(v)}</div>
      </div>`).join("")
  }

  _summarizeHours() {
    const dayLabels = {
      mon: "Lendi",   tue: "Madi",     wed: "Mèkredi", thu: "Jedi",
      fri: "Vandredi", sat: "Samdi",   sun: "Dimanch"
    }
    const open = []
    Object.keys(dayLabels).forEach(day => {
      const toggle = this.element.querySelector(`[id$="_${day}_toggle"]`)
      if (!toggle || !toggle.checked) return
      const opens  = this.element.querySelectorAll(`input[name^="election_mission_participation[operating_hours][${day}]"][name$="[open]"]`)
      const closes = this.element.querySelectorAll(`input[name^="election_mission_participation[operating_hours][${day}]"][name$="[close]"]`)
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
