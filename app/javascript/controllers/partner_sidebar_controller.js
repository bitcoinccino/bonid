import { Controller } from "@hotwired/stimulus"

// Partner sidebar controller for mobile toggle
// Works with both partner portal and officer portal sidebars
export default class extends Controller {
  connect() {
    // Listen for external toggle events (from navbar hamburger)
    document.addEventListener("partner-sidebar:toggle", this.toggle.bind(this))
  }

  disconnect() {
    document.removeEventListener("partner-sidebar:toggle", this.toggle.bind(this))
  }

  getSidebarElements() {
    // Support both partner and officer sidebar IDs
    const sidebar = document.getElementById("partnerSidebar") || document.getElementById("officerSidebar")
    const backdrop = document.getElementById("partnerSidebarBackdrop") || document.getElementById("officerSidebarBackdrop")
    return { sidebar, backdrop }
  }

  toggle() {
    const { sidebar, backdrop } = this.getSidebarElements()

    if (sidebar && backdrop) {
      sidebar.classList.toggle("show")
      backdrop.classList.toggle("show")

      // Prevent body scroll when sidebar is open
      if (sidebar.classList.contains("show")) {
        document.body.style.overflow = "hidden"
      } else {
        document.body.style.overflow = ""
      }
    }
  }

  close() {
    const { sidebar, backdrop } = this.getSidebarElements()

    if (sidebar && backdrop) {
      sidebar.classList.remove("show")
      backdrop.classList.remove("show")
      document.body.style.overflow = ""
    }
  }

  open() {
    const { sidebar, backdrop } = this.getSidebarElements()

    if (sidebar && backdrop) {
      sidebar.classList.add("show")
      backdrop.classList.add("show")
      document.body.style.overflow = "hidden"
    }
  }
}
