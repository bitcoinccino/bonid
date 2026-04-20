import { Controller } from "@hotwired/stimulus"

// Country-aware phone field. Pairs an ISO2 country picker with a phone
// digits input. The picker's selected option carries `data-dial-code`
// (the +NNN prefix), which we mirror into the visible input-group
// prefix display + a hidden `*_phone_country_code` field that gets
// submitted alongside the digits.
//
// The composed E.164 form ("+NNN" + digits) is rebuilt on the server
// from the two parts; the digits field stores only the national number.
export default class extends Controller {
  static targets = ["country", "prefix", "digits", "dialCodeHidden"]
  static values  = { defaultCountry: { type: String, default: "" } }

  connect() {
    if (this.defaultCountryValue && !this.countryTarget.value) {
      this.countryTarget.value = this.defaultCountryValue.toUpperCase()
    }
    this._sync()
  }

  // Action: data-action="change->phone-country#countryChanged"
  countryChanged() { this._sync() }

  // Public API: lets sibling controllers (wizard companions) push a
  // country in (e.g. on diaspora country change for polling-center).
  setCountry(iso2) {
    if (!iso2) return
    const upper = iso2.toUpperCase()
    if (this.countryTarget.value === upper) return
    this.countryTarget.value = upper
    this._sync()
  }

  _sync() {
    const opt = this.countryTarget.selectedOptions[0]
    const dial = opt ? (opt.getAttribute("data-dial-code") || "") : ""
    if (this.hasPrefixTarget) {
      this.prefixTarget.textContent = dial ? `+${dial}` : "+—"
    }
    if (this.hasDialCodeHiddenTarget) {
      this.dialCodeHiddenTarget.value = dial ? `+${dial}` : ""
    }
  }
}
