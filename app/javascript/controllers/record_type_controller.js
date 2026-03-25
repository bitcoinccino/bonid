import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="record-type"
export default class extends Controller {
  reload(event) {
    const type = event.target.value
    if (!type) return

    const frame = document.getElementById("record_form_frame")
    if (frame) {
      // Turbo will automatically fetch and swap only the frame
      const url = `/citizens/verification_records/new?record_type=${encodeURIComponent(type)}`
      frame.src = url
    }
  }
}
