// app/javascript/controllers/id_switcher_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "sex",
    "nationality",
    "idType",
    "cinUniqueId",
    "cinCardNumber",
    "passportNumber",
    "cinFields",
    "passportField",
    "countrySelect",
    "diasporaFields",
    "diasporaProofFields"
  ]

  connect() {
    this.updateNationality()
    this.toggleCinField()
    this.toggle()  // <-- IMPORTANT: ensures ID selection works on load
    this.toggleDiaspora() // Handle diaspora fields on load
  }

  // -----------------------------
  // AUTO-NATIONALITY
  // -----------------------------
  updateNationality() {
    if (!this.hasSexTarget || !this.hasNationalityTarget) return

    const sex = this.sexTarget.value
    this.nationalityTarget.value =
      sex === "male" ? "Haïtien" :
      sex === "female" ? "Haïtienne" : ""
  }

  // -----------------------------
  // CIN UNIQUE FIELD
  // (only visible if CIN selected)
  // -----------------------------
  toggleCinField() {
    if (!this.hasIdTypeTarget || !this.hasCinUniqueIdTarget) return

    const show = this.idTypeTarget.value === "cin"
    this.cinUniqueIdTarget.style.display = show ? "block" : "none"
  }

  // -----------------------------
  // ID TYPE SWITCHER (MAIN FIX)
  // Show CIN fields or Passport fields
  // -----------------------------
  toggle() {
    if (!this.hasIdTypeTarget) return

    const type = this.idTypeTarget.value

    if (this.hasCinFieldsTarget)
      this.cinFieldsTarget.style.display = type === "cin" ? "" : "none"

    if (this.hasPassportFieldTarget)
      this.passportFieldTarget.style.display = type === "passport" ? "" : "none"

    // also toggle CIN unique field
    this.toggleCinField()
  }

  // -----------------------------
  // CIN CARD NUMBER FORMAT
  // -----------------------------
  formatCinCardNumber() {
    if (!this.hasCinCardNumberTarget) return

    let raw = this.cinCardNumberTarget.value.replace(/[^A-Za-z0-9]/g, "")
    raw = raw.toUpperCase()

    this.cinCardNumberTarget.value = raw
  }

  // -----------------------------
  // PASSPORT FORMAT
  // -----------------------------
  formatPassport() {
    if (!this.hasPassportNumberTarget) return

    let raw = this.passportNumberTarget.value
      .replace(/[^A-Za-z0-9]/g, "")
      .toUpperCase()

    this.passportNumberTarget.value = raw
  }

  // -----------------------------
  // DIASPORA TOGGLE
  // When country != HT:
  //   - Show diaspora document fields
  //   - Force ID type to Passport only (diaspora unlikely to have CIN)
  //   - Show proof of address options
  // -----------------------------
  toggleDiaspora() {
    if (!this.hasCountrySelectTarget) return

    const isDiaspora = this.countrySelectTarget.value !== "HT" && this.countrySelectTarget.value !== ""

    // Show/hide diaspora fields
    if (this.hasDiasporaFieldsTarget) {
      this.diasporaFieldsTarget.style.display = isDiaspora ? "block" : "none"
    }

    // Show/hide diaspora proof of address
    if (this.hasDiasporaProofFieldsTarget) {
      this.diasporaProofFieldsTarget.style.display = isDiaspora ? "block" : "none"
    }

    // Force Passport for diaspora
    if (this.hasIdTypeTarget) {
      if (isDiaspora) {
        this.idTypeTarget.value = "passport"
        // Disable CIN option
        const cinOption = this.idTypeTarget.querySelector("option[value='cin']")
        if (cinOption) cinOption.disabled = true
        this.toggle()
      } else {
        const cinOption = this.idTypeTarget.querySelector("option[value='cin']")
        if (cinOption) cinOption.disabled = false
      }
    }
  }
}
