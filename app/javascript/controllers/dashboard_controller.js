// app/javascript/controllers/dashboard_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "tab", "tabButton", "spinner", "content",
    "searchInput", "activityList", "activityRow"
  ];

  connect() {
    console.log("📂 DashboardController connected");
    this.loading = false;
    this.showInitialTab();
  }

  showInitialTab() {
    const activeButton = this.tabButtonTargets.find(btn => btn.classList.contains("active"));
    if (activeButton) {
      this.switchTab({ currentTarget: activeButton });
    }
  }

  switchTab(event) {
    if (this.loading) return;

    const clickedButton = event.currentTarget;
    const targetTabId = clickedButton.dataset.targetTab;
    const reload = clickedButton.dataset.reload === "true";

    // Hide all tabs and spinners
    this.tabTargets.forEach(tab => {
      tab.classList.remove("visible");
      tab.classList.add("hidden");
      tab.setAttribute("aria-hidden", "true");
    });

    this.spinnerTargets.forEach(spinner => {
      spinner.classList.add("d-none");
    });

    this.tabButtonTargets.forEach(btn => {
      btn.classList.remove("active");
      btn.setAttribute("aria-current", "false");
    });

    // Activate current tab button
    clickedButton.classList.add("active");
    clickedButton.setAttribute("aria-current", "true");

    // Show spinner
    const spinnerKey = targetTabId.replace("#", "");
    const spinner = this.spinnerTargets.find(s => s.dataset.spinnerFor === spinnerKey);
    if (spinner) spinner.classList.remove("d-none");

    // Show selected tab
    const selectedTab = this.tabTargets.find(tab => `#${tab.id}` === targetTabId);
    if (selectedTab) {
      selectedTab.classList.remove("hidden");
      selectedTab.classList.add("visible");
      selectedTab.setAttribute("aria-hidden", "false");

      const frame = selectedTab.querySelector("turbo-frame");
      if (frame && reload) {
        this.loading = true;
        frame.src = frame.dataset.src;
      } else if (spinner) {
        spinner.classList.add("d-none"); // Hide spinner if already loaded
      }

      clickedButton.dataset.reload = "false";
    }
  }

  frameLoaded(event) {
    this.loading = false;
    const frame = event.target;
    const spinnerKey = frame.id.replace("_frame", "");
    const spinner = this.spinnerTargets.find(s => s.dataset.spinnerFor === spinnerKey);
    if (spinner) spinner.classList.add("d-none");
  }

  // ── Activity Search/Filter ──
  filterActivity() {
    if (!this.hasSearchInputTarget) return;

    const query = this.searchInputTarget.value.trim().toLowerCase();

    this.activityRowTargets.forEach(row => {
      if (!query) {
        row.style.display = "";
        return;
      }

      const name = (row.dataset.name || "").toLowerCase();
      const bonid = (row.dataset.bonid || "").toLowerCase();
      const match = name.includes(query) || bonid.includes(query);
      row.style.display = match ? "" : "none";
    });
  }
}
