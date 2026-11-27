import { Controller } from "@hotwired/stimulus"

// Submits the surrounding form as soon as a field changes — used for
// settings that save on pick (e.g. Paramèt → Lang dropdown) so there's no
// separate Save button.
//
// Markup:
//   <form data-controller="auto-submit">
//     <select data-action="change->auto-submit#submit">…</select>
//   </form>
export default class extends Controller {
  submit() {
    if (this.submitting) return
    this.submitting = true
    this.element.requestSubmit()
  }
}
