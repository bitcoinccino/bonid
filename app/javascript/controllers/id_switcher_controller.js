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
    "diasporaProofFields",
    "idNumber",
    "idNumberHint",
    "ninu",
    "ninuInput",
    "idNumberLabel",
    "idNumberField"
  ]

  connect() {
    this.updateNationality()
    this.toggleCinField()
    this.toggle()  // <-- IMPORTANT: ensures ID selection works on load
    this.toggleDiaspora() // Handle diaspora fields on load
    this.toggleFields()   // Profile ID step: NINU, number label + example
  }

  // -----------------------------
  // PROFILE ID STEP
  // Show NINU only for passports, and the number example/placeholder
  // for the selected type only.
  // -----------------------------
  toggleFields(event) {
    if (!this.hasIdTypeTarget) return
    const type = this.idTypeTarget.value

    // "Numéro de CIN" / "Numéro du passeport" so it's never confused with NINU.
    if (this.hasIdNumberLabelTarget) {
      const d = this.idNumberLabelTarget.dataset
      const text = type === "cin" ? d.labelCin : type === "passport" ? d.labelPassport : d.labelNone
      // Keep simple_form's required marker (<abbr>) if present.
      const abbr = this.idNumberLabelTarget.querySelector("abbr")
      this.idNumberLabelTarget.textContent = text + " "
      if (abbr) this.idNumberLabelTarget.appendChild(abbr)
    }

    // When the citizen switches type, drop a number that can't belong to the
    // new document (e.g. a 10-digit CIN number left in place for a passport).
    // Only on a real change, never on page load, so saved data is untouched.
    if (event && this.hasIdNumberTarget) {
      const v = this.idNumberTarget.value.replace(/[^A-Za-z0-9]/g, "")
      const fits = type === "cin" ? (/^\d{10}$/.test(v) || /^[A-Za-z0-9]{9}$/.test(v))
                 : type === "passport" ? /^[A-Za-z0-9]{6,9}$/.test(v) : true
      if (v && !fits) this.idNumberTarget.value = ""
    }

    if (this.hasNinuTarget)
      this.ninuTarget.style.display = type === "passport" ? "" : "none"

    // Passports: NINU only. The ID number field is hidden (the server stores
    // the NINU as the ID number) and must not stay required while hidden.
    if (this.hasIdNumberFieldTarget)
      this.idNumberFieldTarget.style.display = type === "passport" ? "none" : ""
    if (this.hasIdNumberTarget)
      this.idNumberTarget.required = type === "cin"

    // NINU is required only while Passport is selected; never leave a
    // hidden field required (the browser would block the submit).
    if (this.hasNinuInputTarget) {
      this.ninuInputTarget.required = type === "passport"
    }

    if (this.hasIdNumberTarget) {
      const ph = type === "cin" ? this.idNumberTarget.dataset.placeholderCin
               : type === "passport" ? this.idNumberTarget.dataset.placeholderPassport : ""
      this.idNumberTarget.placeholder = ph || ""
    }

    if (this.hasIdNumberHintTarget) {
      const d = this.idNumberHintTarget.dataset
      // Translated strings from our own locale files (may contain <strong>).
      this.idNumberHintTarget.innerHTML =
        type === "cin" ? d.hintCin : type === "passport" ? d.hintPassport : d.hintNone
    }
  }

  // Uppercase letters and digits only (CIN: T1K2N8697, passport: R10772334)
  formatIdNumber() {
    if (!this.hasIdNumberTarget) return
    const el = this.idNumberTarget
    const cleaned = el.value.replace(/[^A-Za-z0-9]/g, "").toUpperCase()
    if (cleaned !== el.value) el.value = cleaned
  }

  // NINU: digits only, 10 max
  formatNinu(event) {
    const el = event.target
    const cleaned = el.value.replace(/\D/g, "").slice(0, 10)
    if (cleaned !== el.value) el.value = cleaned
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
