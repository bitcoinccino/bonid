import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["issuingAuthority", "sex", "nationality", "idType"]

  connect() {
    this.toggle()
    this.updateNationality()
  }

  toggle() {
    if (!this.hasIdTypeTarget || !this.hasIssuingAuthorityTarget) return

    const selected = this.idTypeTarget.value.toLowerCase()
    this.issuingAuthorityTarget.style.display = selected === "passport" ? "block" : "none"
  }

  updateNationality() {
    if (!this.hasSexTarget || !this.hasNationalityTarget) return

    const sex = this.sexTarget.value
    this.nationalityTarget.value =
      sex === "M" ? "Haïtien" :
      sex === "F" ? "Haïtienne" :
      ""
  }
}

