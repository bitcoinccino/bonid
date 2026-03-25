import { Controller } from "@hotwired/stimulus"

/**
 * FAQ Controller
 * Handles search filtering, category filtering, expand/collapse all,
 * and smooth accordion interactions for the citizen FAQ page.
 */
export default class extends Controller {
  static targets = [
    "searchInput",
    "clearBtn",
    "categoryBtn",
    "faqItem",
    "expandToggle",
    "noResults",
    "counter"
  ]

  static values = {
    activeCategory: { type: String, default: "all" }
  }

  connect() {
    this.updateCounter()
  }

  // ── Search ──────────────────────────────────────────────
  search() {
    const query = this.searchInputTarget.value.trim().toLowerCase()

    // Toggle clear button visibility
    if (this.hasClearBtnTarget) {
      this.clearBtnTarget.classList.toggle("d-none", query.length === 0)
    }

    // Reset category filter when searching
    if (query.length > 0) {
      this.activeCategoryValue = "all"
      this.highlightCategoryBtn("all")
    }

    this.filterItems()
  }

  searchTrending(event) {
    const query = event.currentTarget.dataset.query || ""
    this.searchInputTarget.value = query
    this.search()
  }

  clearSearch() {
    this.searchInputTarget.value = ""
    if (this.hasClearBtnTarget) {
      this.clearBtnTarget.classList.add("d-none")
    }
    this.filterItems()
    this.searchInputTarget.focus()
  }

  // ── Category Filter ─────────────────────────────────────
  filterByCategory(event) {
    const category = event.currentTarget.dataset.category
    this.activeCategoryValue = category

    // Clear search when switching categories
    this.searchInputTarget.value = ""

    this.highlightCategoryBtn(category)
    this.filterItems()
  }

  highlightCategoryBtn(activeKey) {
    this.categoryBtnTargets.forEach(btn => {
      const isActive = btn.dataset.category === activeKey
      btn.classList.toggle("active", isActive)
    })
  }

  // ── Expand / Collapse All ───────────────────────────────
  toggleAll() {
    const visibleItems = this.visibleItems()
    const anyOpen = visibleItems.some(el => el.hasAttribute("open"))

    visibleItems.forEach(el => {
      if (anyOpen) {
        el.removeAttribute("open")
      } else {
        el.setAttribute("open", "")
      }
    })

    this.updateToggleLabel(!anyOpen)
  }

  updateToggleLabel(expanded) {
    if (!this.hasExpandToggleTarget) return
    const label = this.expandToggleTarget.querySelector("[data-label]")
    const icon = this.expandToggleTarget.querySelector("i")
    if (label) {
      label.textContent = expanded
        ? this.expandToggleTarget.dataset.collapseText
        : this.expandToggleTarget.dataset.expandText
    }
    if (icon) {
      icon.className = expanded ? "ri-contract-up-down-line me-1" : "ri-expand-up-down-line me-1"
    }
  }

  // ── Core Filter Logic ───────────────────────────────────
  filterItems() {
    const query = this.searchInputTarget.value.trim().toLowerCase()
    const category = this.activeCategoryValue
    let visibleCount = 0

    this.faqItemTargets.forEach(item => {
      const matchesCategory = category === "all" || item.dataset.category === category
      const text = (item.textContent || "").toLowerCase()
      const matchesSearch = query.length === 0 || text.includes(query)

      const visible = matchesCategory && matchesSearch
      item.style.display = visible ? "" : "none"

      // Auto-open matching items during search
      if (visible && query.length > 0) {
        item.setAttribute("open", "")
      }

      if (visible) visibleCount++
    })

    // Show/hide no results message
    if (this.hasNoResultsTarget) {
      this.noResultsTarget.style.display = visibleCount === 0 ? "" : "none"
    }

    this.updateCounter(visibleCount)
    this.updateToggleLabel(false)
  }

  // ── Helpers ─────────────────────────────────────────────
  visibleItems() {
    return this.faqItemTargets.filter(el => el.style.display !== "none")
  }

  updateCounter(count) {
    if (!this.hasCounterTarget) return
    const total = count !== undefined ? count : this.faqItemTargets.length
    this.counterTarget.textContent = `${total} question${total !== 1 ? "s" : ""}`
  }
}
