// app/javascript/controllers/postal_code_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["communalSectionSelect", "postalCodeInput"]

  update() {
    const sectionId = this.communalSectionSelectTarget.value
    if (!sectionId) {
      this._setPostalCode("")
      return
    }

    fetch(`/communal_sections/${sectionId}/postal_code`)
      .then(response => {
        if (!response.ok) throw new Error("Network response was not ok")
        return response.json()
      })
      .then(data => {
        this._setPostalCode(data.postal_code || "HT0000")
      })
      .catch(error => {
        console.error("Postal code fetch error:", error)
        this._setPostalCode("HT0000")
      })
  }

  _setPostalCode(code) {
    this.postalCodeInputTarget.value = code
  }
}

