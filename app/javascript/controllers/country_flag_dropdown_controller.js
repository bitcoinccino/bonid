import { Controller } from "@hotwired/stimulus"

// Custom country picker that shows real flag images (not the regional-
// indicator emoji glyph rendered by the OS font, which falls back to
// "HT" letters on systems without flag emoji support like Windows).
//
// Wraps a hidden <select> still owned by phone-country-controller — the
// select stays in the DOM so the existing setCountry()/sync() pipeline
// keeps working untouched. Picking an item from the dropdown:
//   1. updates the trigger button's flag <img> + dial code
//   2. sets the hidden select's value
//   3. fires `change` so phone-country mirrors +NNN into the prefix
//
// Flag images come from flagcdn.com (PNG by ISO2 code, public CDN).
export default class extends Controller {
  static targets = ["trigger", "triggerFlag", "triggerCode", "search", "item", "hiddenSelect"]

  connect() {
    // Initial sync — make sure the trigger reflects whatever the
    // hidden select was rendered with.
    if (this.hasHiddenSelectTarget && this.hiddenSelectTarget.value) {
      this._syncTrigger(this.hiddenSelectTarget.value, this._dialFor(this.hiddenSelectTarget.value))
    }
  }

  // Action: data-action="country-flag-dropdown#select" on each menu item
  select(event) {
    const btn = event.currentTarget
    const iso2 = btn.dataset.iso2
    const dial = btn.dataset.dialCode
    if (!iso2) return

    if (this.hasHiddenSelectTarget) {
      this.hiddenSelectTarget.value = iso2
      this.hiddenSelectTarget.dispatchEvent(new Event("change", { bubbles: true }))
    }
    this._syncTrigger(iso2, dial)
  }

  // Action: data-action="input->country-flag-dropdown#filter" on the search box
  filter(event) {
    const q = event.target.value.toLowerCase().trim()
    this.itemTargets.forEach(item => {
      const name = (item.dataset.countryName || "").toLowerCase()
      const code = item.dataset.dialCode || ""
      const iso2 = (item.dataset.iso2 || "").toLowerCase()
      const matches = !q || name.includes(q) || code.includes(q) || iso2.includes(q)
      item.classList.toggle("d-none", !matches)
    })
  }

  _syncTrigger(iso2, dial) {
    if (this.hasTriggerFlagTarget) {
      const code = iso2.toLowerCase()
      this.triggerFlagTarget.src    = `https://flagcdn.com/20x15/${code}.png`
      this.triggerFlagTarget.srcset = `https://flagcdn.com/40x30/${code}.png 2x`
      this.triggerFlagTarget.alt    = iso2
    }
    if (this.hasTriggerCodeTarget) {
      this.triggerCodeTarget.textContent = dial ? `+${dial}` : "+—"
    }
  }

  _dialFor(iso2) {
    if (!this.hasHiddenSelectTarget) return ""
    const opt = Array.from(this.hiddenSelectTarget.options).find(o => o.value === iso2)
    return opt ? (opt.getAttribute("data-dial-code") || "") : ""
  }
}
