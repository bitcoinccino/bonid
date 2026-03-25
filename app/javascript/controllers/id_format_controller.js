import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "cin",
    "passport",
    "phone",
    "sex",
    "nationality",
    "birthdate"
  ]

  connect() {
    this.autoNationality()
    this.formatCin()
    this.formatPassport()
    this.formatPhone()
    this.formatBirthdate()
  }

  // -----------------------------------------------------
  // 1. AUTO FORMAT CIN (NN-NN-NNNN)
  // -----------------------------------------------------
  formatCin() {
    if (!this.hasCinTarget) return

    let v = this.cinTarget.value.replace(/\D/g, "")
    if (v.length > 2) v = v.slice(0, 2) + "-" + v.slice(2)
    if (v.length > 5) v = v.slice(0, 5) + "-" + v.slice(5)
    this.cinTarget.value = v.slice(0, 10)
  }

  // -----------------------------------------------------
  // 2. AUTO FORMAT PASSPORT (Letter + 8 digits)
  // -----------------------------------------------------
  formatPassport() {
    if (!this.hasPassportTarget) return

    let v = this.passportTarget.value.toUpperCase()

    // First char must be letter
    v = v.replace(/[^A-Z0-9]/g, "")

    if (v.length === 1) {
      v = v.replace(/[^A-Z]/g, "")
    } else {
      v = v[0].replace(/[^A-Z]/g, "") + v.slice(1).replace(/\D/g, "")
    }

    this.passportTarget.value = v.slice(0, 9)
  }

  // -----------------------------------------------------
  // 3. AUTO FORMAT PHONE (+509 1234 5678)
  // -----------------------------------------------------
  formatPhone() {
    if (!this.hasPhoneTarget) return

    let v = this.phoneTarget.value.replace(/\D/g, "")

    if (v.startsWith("509")) {
      v = v.slice(0)
    } else if (v.startsWith("09")) {
      v = "509" + v.slice(2)
    } else if (v.startsWith("9")) {
      v = "509" + v
    }

    v = "+509 " + (v.slice(3, 7) || "") + " " + (v.slice(7, 11) || "")

    this.phoneTarget.value = v.trim()
  }

  // -----------------------------------------------------
  // 4. AUTO FORMAT BIRTHDATE (YYYY-MM-DD)
  // -----------------------------------------------------
  formatBirthdate() {
    if (!this.hasBirthdateTarget) return

    let v = this.birthdateTarget.value.replace(/\D/g, "")
    if (v.length >= 4) v = v.slice(0, 4) + "-" + v.slice(4)
    if (v.length >= 7) v = v.slice(0, 7) + "-" + v.slice(7)
    this.birthdateTarget.value = v.slice(0, 10)
  }

  // -----------------------------------------------------
  // 5. AUTO NATIONALITY SETTER
  // -----------------------------------------------------
  autoNationality() {
    if (!this.hasSexTarget || !this.hasNationalityTarget) return

    const val = this.sexTarget.value
    let nation = ""

    if (val === "male") nation = "Haïtien"
    else if (val === "female") nation = "Haïtienne"

    // Only auto-set when empty
    if (!this.nationalityTarget.value.trim()) {
      this.nationalityTarget.value = nation
    }
  }
}
