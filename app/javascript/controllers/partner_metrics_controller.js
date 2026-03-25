import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"
Chart.register(...registerables)

/**
 * Partner Metrics Dashboard Controller
 * - Fetches live metrics securely from /partner_portal/metrics (session-authenticated)
 * - Auto-refreshes every 30s
 * - Updates summary, charts, and quota progress bar
 */
export default class extends Controller {
  static targets = [
    "total", "success", "failed", "latency",
    "endpointChart", "statusChart",
    "quotaLabel", "quotaBar"
  ]

  connect() {
    this.fetchMetrics()
    this.interval = setInterval(() => this.fetchMetrics(), 30000) // refresh every 30s
    this.initTooltips()
  }

  disconnect() {
    clearInterval(this.interval)
  }

  // Securely fetch partner metrics via internal proxy
  async fetchMetrics() {
    try {
      const response = await fetch("/partner_portal/metrics", {
        headers: { "Accept": "application/json" },
        credentials: "same-origin" // ensure Devise session is included
      })

      if (!response.ok) {
        console.warn("Metrics request failed:", response.status)
        return
      }

      const data = await response.json()
      if (!data || !data.metrics) return

      this.updateSummary(data.metrics)
      this.updateQuota(data)
      this.renderCharts(data)
    } catch (error) {
      console.error("Error fetching metrics:", error)
    }
  }

  // === Update Summary Numbers ===
  updateSummary(metrics) {
    this.totalTarget.textContent = metrics.total_requests ?? "–"
    this.successTarget.textContent = metrics.successful_requests ?? "–"
    this.failedTarget.textContent = metrics.failed_requests ?? "–"
    this.latencyTarget.textContent = metrics.avg_latency_ms
      ? metrics.avg_latency_ms.toFixed(2)
      : "–"
  }

  // === Update Quota / Rate-Limit Progress ===
  updateQuota(data) {
    const metrics = data.metrics || {}
    const used = metrics.total_requests || 0
    const quota = metrics.daily_quota || data.rate_limit?.limit || 10000
    const remaining = data.rate_limit?.remaining ?? Math.max(quota - used, 0)
    const percent = Math.min((used / quota) * 100, 100)

    // Update label
    if (this.hasQuotaLabelTarget)
      this.quotaLabelTarget.textContent =
        `${used.toLocaleString()} / ${quota.toLocaleString()} (${remaining.toLocaleString()} left)`

    // Update progress bar
    if (this.hasQuotaBarTarget) {
      this.quotaBarTarget.style.width = `${percent}%`
      const bar = this.quotaBarTarget
      bar.classList.remove("bg-success", "bg-warning", "bg-danger")
      if (percent < 70) bar.classList.add("bg-success")
      else if (percent < 90) bar.classList.add("bg-warning")
      else bar.classList.add("bg-danger")
    }
  }

  // === Render All Charts ===
  renderCharts(data) {
    const endpoints = data.endpoint_breakdown || []

    // Endpoint Requests Chart
    this.renderChart(
      this.endpointChartTarget,
      "bar",
      endpoints.map(e => e.endpoint),
      endpoints.map(e => e.requests),
      "Requests per Endpoint",
      "#04328C"
    )

    // Success/Failure Status Chart
    this.renderChart(
      this.statusChartTarget,
      "doughnut",
      ["Success", "Failed"],
      [
        data.metrics.successful_requests || 0,
        data.metrics.failed_requests || 0
      ],
      "Status Breakdown",
      ["#1A936F", "#E53E3E"]
    )
  }

  // === Render Individual Chart ===
  renderChart(canvas, type, labels, dataset, label, colors) {
    if (!canvas) return
    const ctx = canvas.getContext("2d")
    if (canvas._chart) canvas._chart.destroy()

    canvas._chart = new Chart(ctx, {
      type,
      data: {
        labels,
        datasets: [{
          label,
          data: dataset,
          backgroundColor: Array.isArray(colors) ? colors : [colors],
          borderColor: colors,
          borderWidth: 1
        }]
      },
      options: {
        plugins: { legend: { display: true } },
        responsive: true,
        maintainAspectRatio: false
      }
    })
  }

  // === Bootstrap Tooltip Support ===
  initTooltips() {
    document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(el => {
      new bootstrap.Tooltip(el)
    })
  }
}
