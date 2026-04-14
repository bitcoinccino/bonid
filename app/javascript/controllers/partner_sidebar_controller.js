import { Controller } from "@hotwired/stimulus"

// Partner sidebar controller for mobile toggle
// Works with both partner portal and officer portal sidebars
//
// The backdrop starts with style="display:none" in HTML to prevent
// an invisible full-viewport overlay from blocking all page clicks.
// This controller manages display + .show class together.
export default class extends Controller {
  connect() {
    this._boundToggle = this.toggle.bind(this)
    document.addEventListener("partner-sidebar:toggle", this._boundToggle)
  }

  disconnect() {
    document.removeEventListener("partner-sidebar:toggle", this._boundToggle)
  }

  getSidebarElements() {
    const sidebar = document.getElementById("partnerSidebar") || document.getElementById("officerSidebar")
    const backdrop = document.getElementById("partnerSidebarBackdrop") || document.getElementById("officerSidebarBackdrop")
    return { sidebar, backdrop }
  }

  toggle() {
    const { sidebar, backdrop } = this.getSidebarElements()
    if (!sidebar || !backdrop) return

    const isOpen = sidebar.classList.contains("show")

    if (isOpen) {
      this._closeSidebar(sidebar, backdrop)
    } else {
      this._openSidebar(sidebar, backdrop)
    }
  }

  close() {
    const { sidebar, backdrop } = this.getSidebarElements()
    if (!sidebar || !backdrop) return
    this._closeSidebar(sidebar, backdrop)
  }

  open() {
    const { sidebar, backdrop } = this.getSidebarElements()
    if (!sidebar || !backdrop) return
    this._openSidebar(sidebar, backdrop)
  }

  _openSidebar(sidebar, backdrop) {
    sidebar.classList.add("show")
    backdrop.style.display = "block"
    // Allow display:block to paint, then add .show for opacity transition
    requestAnimationFrame(() => backdrop.classList.add("show"))
    document.body.style.overflow = "hidden"
  }

  _closeSidebar(sidebar, backdrop) {
    sidebar.classList.remove("show")
    backdrop.classList.remove("show")
    document.body.style.overflow = ""
    // After opacity transition ends, hide completely
    setTimeout(() => {
      if (!backdrop.classList.contains("show")) {
        backdrop.style.display = "none"
      }
    }, 300)
  }
}
