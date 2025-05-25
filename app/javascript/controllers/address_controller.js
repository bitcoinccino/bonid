// app/javascript/controllers/address_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["department", "arrondissement", "commune", "section", "postalCode"]

  connect() {
    console.log("📍 AddressController connected")
  }

  async loadArrondissements(event) {
    const departmentId = event.target.value
    const slugMap = JSON.parse(event.target.dataset.slugMap || "{}")
    const slug = slugMap[departmentId]
    if (!slug) return

    const response = await fetch(`/departments/${slug}/arrondissements`)
    const data = await response.json()

    this._populate(this.arrondissementTarget, data)
    this._clear(this.communeTarget)
    this._clear(this.sectionTarget)
    this._clearPostal()
  }

  async loadCommunes(event) {
    const id = event.target.value
    if (!id) return

    const response = await fetch(`/arrondissements/${id}/communes`)
    const data = await response.json()

    this._populate(this.communeTarget, data)
    this._clear(this.sectionTarget)
    this._clearPostal()
  }

  async loadCommunalSections(event) {
    const id = event.target.value
    if (!id) return

    const response = await fetch(`/communes/${id}/communal_sections`)
    const data = await response.json()

    this._populate(this.sectionTarget, data)
    this._clearPostal()
  }

  async loadPostalCode(event) {
    const id = event.target.value
    if (!id) return

    const response = await fetch(`/communal_sections/${id}/postal_code`)
    const data = await response.json()
    this.postalCodeTarget.value = data.postal_code || "HT0000"
  }

  _populate(target, items) {
    target.innerHTML = '<option value="">Please select</option>'
    items.forEach(({ id, name }) => {
      const option = document.createElement("option")
      option.value = id
      option.textContent = name
      target.appendChild(option)
    })
  }

  _clear(target) {
    if (target) target.innerHTML = '<option value="">Please select</option>'
  }

  _clearPostal() {
    if (this.hasPostalCodeTarget) this.postalCodeTarget.value = ""
  }
}
