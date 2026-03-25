// app/javascript/controllers/le_search_controller.js
// Global search for Partner Portal Law Enforcement dashboard
// Searches officers, incident reports, and citizen BonIDs

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results"]
  static values  = { url: String }

  connect() {
    this.debounceTimer = null
    this._handleClickOutside = this.closeResults.bind(this)
    document.addEventListener("click", this._handleClickOutside)
  }

  disconnect() {
    document.removeEventListener("click", this._handleClickOutside)
    if (this.debounceTimer) clearTimeout(this.debounceTimer)
  }

  search() {
    const query = this.inputTarget.value.trim()
    if (query.length < 2) {
      this.hideResults()
      return
    }

    clearTimeout(this.debounceTimer)
    this.debounceTimer = setTimeout(() => this.performSearch(query), 300)
  }

  async performSearch(query) {
    // Show loading spinner
    this.resultsTarget.innerHTML = `
      <div class="p-3 text-center">
        <i class="ri-loader-4-line ri-spin" style="color: var(--law-blue); font-size: 1.2rem;"></i>
      </div>
    `
    this.showResults()

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
      const response = await fetch(`${this.urlValue}?q=${encodeURIComponent(query)}`, {
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken || ""
        }
      })

      if (!response.ok) {
        this.hideResults()
        return
      }

      const data = await response.json()
      this.renderResults(data.results)
    } catch (err) {
      console.error("[LE Search] Error:", err)
      this.hideResults()
    }
  }

  renderResults(results) {
    let html = ""

    // Officers
    if (results.officers && results.officers.length > 0) {
      html += `<div class="le-search-group-header"><i class="ri-shield-user-line me-1"></i> Officers</div>`
      results.officers.forEach(o => {
        const statusBadge = o.status === "active"
          ? `<span style="color: var(--law-green); font-size: 0.6rem; font-weight: 600;">Active</span>`
          : o.status === "revoked"
            ? `<span style="color: var(--law-red); font-size: 0.6rem; font-weight: 600;">Revoked</span>`
            : `<span style="color: #D97706; font-size: 0.6rem; font-weight: 600;">${o.status || "Pending"}</span>`
        html += `
          <a href="${o.url}" class="le-search-item">
            <div style="width: 28px; height: 28px; border-radius: 6px; background: rgba(9,44,115,0.08); display: flex; align-items: center; justify-content: center; flex-shrink: 0;">
              <i class="ri-shield-user-line" style="font-size: 0.75rem; color: var(--law-blue);"></i>
            </div>
            <div style="flex: 1; min-width: 0;">
              <div class="fw-medium" style="font-size: 0.8rem;">${this.escapeHtml(o.name)}</div>
              <div class="le-search-item-meta">
                ${this.escapeHtml(o.badge_id || "")}${o.rank ? ` · ${this.escapeHtml(o.rank)}` : ""}
              </div>
            </div>
            ${statusBadge}
          </a>
        `
      })
    }

    // Incident Reports
    if (results.reports && results.reports.length > 0) {
      html += `<div class="le-search-group-header"><i class="ri-file-list-3-line me-1"></i> Incident Reports</div>`
      results.reports.forEach(r => {
        html += `
          <a href="${r.url}" class="le-search-item">
            <div style="width: 28px; height: 28px; border-radius: 6px; background: rgba(217,7,24,0.08); display: flex; align-items: center; justify-content: center; flex-shrink: 0;">
              <i class="ri-file-list-3-line" style="font-size: 0.75rem; color: var(--law-red);"></i>
            </div>
            <div style="flex: 1; min-width: 0;">
              <div class="fw-medium" style="font-size: 0.8rem;">${this.escapeHtml(r.crime_type || "Unknown")}</div>
              <div class="le-search-item-meta" style="font-family: monospace;">
                ${this.escapeHtml(r.report_id || "")}
              </div>
            </div>
            <span style="font-size: 0.6rem; color: var(--mid-gray);">${this.escapeHtml(r.date || "")}</span>
          </a>
        `
      })
    }

    // Citizens
    if (results.citizens && results.citizens.length > 0) {
      html += `<div class="le-search-group-header"><i class="ri-user-line me-1"></i> Citizens</div>`
      results.citizens.forEach(c => {
        html += `
          <div class="le-search-item">
            <div style="width: 28px; height: 28px; border-radius: 6px; background: rgba(73,166,79,0.08); display: flex; align-items: center; justify-content: center; flex-shrink: 0;">
              <i class="ri-user-line" style="font-size: 0.75rem; color: var(--law-green);"></i>
            </div>
            <div style="flex: 1; min-width: 0;">
              <div class="fw-medium" style="font-size: 0.8rem;">${this.escapeHtml(c.name)}</div>
              <div class="le-search-item-meta" style="font-family: monospace; color: var(--law-blue);">
                ${this.escapeHtml(c.bonid || "N/A")}
              </div>
            </div>
          </div>
        `
      })
    }

    if (!html) {
      html = `
        <div class="p-3 text-center">
          <i class="ri-search-line" style="font-size: 1.5rem; color: rgba(9,44,115,0.15);"></i>
          <p class="text-muted mt-1 mb-0" style="font-size: 0.8rem;">No results found</p>
        </div>
      `
    }

    this.resultsTarget.innerHTML = html
    this.showResults()
  }

  showResults() {
    this.resultsTarget.classList.remove("d-none")
  }

  hideResults() {
    this.resultsTarget.classList.add("d-none")
  }

  closeResults(event) {
    if (!this.element.contains(event.target)) {
      this.hideResults()
    }
  }

  clear() {
    this.inputTarget.value = ""
    this.hideResults()
  }

  // Prevent XSS from search results
  escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }
}
