// app/javascript/controllers/api_keys_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["section", "collapseIcon", "codePanel"];

  // ── Toggle collapsible sections (Credentials, Quick Example) ──
  toggleSection(event) {
    const sectionName = event.params.section;
    const section = this.sectionTargets.find(s => s.dataset.section === sectionName);
    const icon = this.collapseIconTargets.find(i => i.dataset.section === sectionName);

    if (section) {
      section.classList.toggle("collapsed");
    }
    if (icon) {
      icon.classList.toggle("collapsed");
    }
  }

  // ── Switch code language tabs (cURL / Python / Node.js) ──
  switchCodeTab(event) {
    event.stopPropagation();
    event.preventDefault();

    const lang = event.currentTarget.dataset.lang;

    // Update tab active state
    const tabs = this.element.querySelectorAll(".code-tab");
    tabs.forEach(tab => tab.classList.remove("active"));
    event.currentTarget.classList.add("active");

    // Show matching code panel
    this.codePanelTargets.forEach(panel => {
      if (panel.dataset.lang === lang) {
        panel.classList.add("active");
        panel.style.display = "block";
      } else {
        panel.classList.remove("active");
        panel.style.display = "none";
      }
    });
  }

  // ── Copy the currently active code example ──
  copyActiveExample(event) {
    const activePanel = this.codePanelTargets.find(p => p.classList.contains("active"));
    if (!activePanel) return;

    const text = activePanel.textContent.trim();
    const btn = event.currentTarget;

    navigator.clipboard.writeText(text).then(() => {
      const original = btn.innerHTML;
      btn.innerHTML = '<i class="ri-check-line me-1"></i>Copied!';
      setTimeout(() => { btn.innerHTML = original; }, 2000);
    });
  }
}
