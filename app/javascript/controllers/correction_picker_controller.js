import { Controller } from "@hotwired/stimulus"

// Correction request form: the citizen ticks what to correct; only the
// ticked fields show as "current → new", and Send stays disabled until at
// least one is ticked. Unticked fields keep their current value server-side
// (NameChangeRequest#keep_unticked_fields), so hidden inputs are harmless.
export default class extends Controller {
  static targets = ["choice", "row", "changes", "submit"]

  connect() {
    this.toggle()
  }

  toggle() {
    const ticked = this.choiceTargets.filter(c => c.checked).map(c => c.value)

    this.rowTargets.forEach(row => {
      const on = ticked.includes(row.dataset.field)
      row.style.display = on ? "" : "none"
      row.querySelectorAll("input").forEach(i => { i.required = on && i.type !== "file" && row.dataset.field !== "middle_name" })
    })

    if (this.hasChangesTarget) this.changesTarget.style.display = ticked.length ? "" : "none"
    if (this.hasSubmitTarget) this.submitTarget.disabled = ticked.length === 0
  }
}
