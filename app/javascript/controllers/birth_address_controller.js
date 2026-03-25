import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["department", "commune"]

  loadCommunes(event) {
    const departmentId = this.departmentTarget.value

    fetch(`/communes?department_id=${departmentId}`, {
      headers: { Accept: "application/json" }
    })
      .then((response) => response.json())
      .then((data) => {
        this.communeTarget.innerHTML = '<option value="">Select Commune</option>'
        data.forEach((commune) => {
          const option = document.createElement("option")
          option.value = commune.id
          option.textContent = commune.name
          this.communeTarget.appendChild(option)
        })
      })
  }
}
