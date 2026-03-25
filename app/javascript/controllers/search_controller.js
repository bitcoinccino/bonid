// app/javascript/controllers/search_controller.js
import { Controller } from "@hotwired/stimulus"
import debounce from "lodash/debounce"


export default class extends Controller {
  static targets = ["input", "table", "row", "clear", "noResults"]

  connect() {
    console.log("SearchController connected", this.element, new Date().toLocaleString("en-US", { timeZone: "America/New_York" }));
    this.toggleClear();
    this.debouncedFilter = debounce(this.filter.bind(this), 300);
    this.inputTarget.addEventListener("input", this.debouncedFilter);
    this.createLiveRegion();
  }

  disconnect() {
    this.inputTarget.removeEventListener("input", this.debouncedFilter);
  }

  filter() {
    const query = this.inputTarget.value.trim().toLowerCase();
    console.log("Filtering reports with query:", query, "at:", new Date().toLocaleString("en-US", { timeZone: "America/New_York" }));

    let visibleRows = 0;
    this.rowTargets.forEach(row => {
      const bonid = row.cells[1].textContent.toLowerCase();
      const crimeType = row.cells[2].textContent.toLowerCase();
      const description = row.cells[3].textContent.toLowerCase();
      const matches = bonid.includes(query) || crimeType.includes(query) || description.includes(query);
      row.classList.toggle("d-none", !matches);
      if (matches) visibleRows++;
    });

    if (visibleRows === 0 && query) {
      if (!this.noResultsTarget) {
        this.tableTarget.insertAdjacentHTML("afterend", `
          <p class="text-gray-500 dark:text-gray-400 text-center py-4" data-search-target="noResults" aria-live="polite">
            No reports found matching "${query}".
          </p>
        `);
      }
    } else if (this.hasNoResultsTarget) {
      this.noResultsTarget.remove();
    }

    this.liveRegion.textContent = query
      ? `${visibleRows} report${visibleRows === 1 ? "" : "s"} found for query "${query}".`
      : "All reports displayed.";
  }

  toggleClear() {
    if (this.hasClearTarget) {
      this.clearTarget.classList.toggle("d-none", !this.inputTarget.value.trim());
    }
  }

  clearSearch() {
    this.inputTarget.value = "";
    this.debouncedFilter();
    this.toggleClear();
    this.inputTarget.focus();
  }

  copyLink(event) {
    event.preventDefault();
    const reportUrl = event.target.dataset.reportUrl;
    const reportId = event.target.dataset.reportId;

    navigator.clipboard.writeText(reportUrl).then(() => {
      console.log(`Copied link for report ${reportId}: ${reportUrl}`, "at:", new Date().toLocaleString("en-US", { timeZone: "America/New_York" }));
      const originalText = event.target.innerHTML;
      event.target.innerHTML = '<i class="ri-checkbox-circle-line mr-2"></i> Link Copied!';
      setTimeout(() => {
        event.target.innerHTML = originalText;
      }, 2000);
      this.liveRegion.textContent = `Link for report ${reportId} copied to clipboard.`;
    }).catch(err => {
      console.error("Failed to copy link:", err, "at:", new Date().toLocaleString("en-US", { timeZone: "America/New_York" }));
      alert("Failed to copy link. Please try again.");
    });
  }

  createLiveRegion() {
    this.liveRegion = document.createElement("div");
    this.liveRegion.setAttribute("aria-live", "polite");
    this.liveRegion.setAttribute("class", "sr-only");
    document.body.appendChild(this.liveRegion);
  }
}