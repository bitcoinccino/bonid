import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    setTimeout(() => {
      this.element.classList.remove("show")
      this.element.classList.add("fade")
    }, 5000)
  }
}
