// app/javascript/controllers/select_all_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox"]

  connect() {
    // Optional: console.log("SelectAll controller connected")
  }

  selectInitial() {
    this.selectByType("initial")
  }

  selectResubmission() {
    this.selectByType("resubmission")
  }

  selectReissue() {
    this.selectByType("reissue")
  }

  clearAll() {
    this.checkboxTargets.forEach((checkbox) => (checkbox.checked = false))
  }

  selectByType(type) {
    this.checkboxTargets.forEach((checkbox) => {
      checkbox.checked = checkbox.dataset.type === type
    })
  }
}
