import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

export default class extends Controller {
  static values = {
    endpoint: Object,
    daily: Object,
    refreshUrl: String
  }

  static targets = ["updatedLabel", "timer"]

  connect() {
    this.haitianBlue = "#04328C"
    this.palmGreen = "#1A936F"
    this.gold = "#FFD700"
    this.red = "#E53E3E"
    this.coral = "#ED8936"

    this.lastUpdatedAt = new Date()
    this.updateTimerText()

    this.renderCharts()

    // Refresh charts every 30 seconds
    this.refreshInterval = setInterval(() => this.refreshData(), 30000)
    // Update the timer label every second
    this.timerInterval = setInterval(() => this.updateTimerText(), 1000)
  }

  disconnect() {
    clearInterval(this.refreshInterval)
    clearInterval(this.timerInterval)
    if (this.endpointChart) this.endpointChart.destroy()
    if (this.dailyChart) this.dailyChart.destroy()
  }

  renderCharts() {
    if (this.endpointChart) this.endpointChart.destroy()
    if (this.dailyChart) this.dailyChart.destroy()

    const endpointCtx = this.element.querySelector("#endpointChart")
    const dailyCtx = this.element.querySelector("#dailyChart")
    if (!endpointCtx || !dailyCtx) return

    // === Endpoint Chart ===
    this.endpointChart = new Chart(endpointCtx, {
      type: "bar",
      data: {
        labels: Object.keys(this.endpointValue || {}),
        datasets: [{
          label: "API Calls per Endpoint",
          data: Object.values(this.endpointValue || {}),
          backgroundColor: this.haitianBlue,
          borderRadius: 6
        }]
      },
      options: {
        responsive: true,
        animation: { duration: 800, easing: "easeOutQuart" },
        plugins: {
          legend: { display: false },
          tooltip: {
            backgroundColor: this.haitianBlue,
            titleColor: "#fff",
            bodyColor: "#fff",
            cornerRadius: 8
          }
        },
        scales: {
          y: { beginAtZero: true, grid: { color: "rgba(0,0,0,0.05)" } },
          x: { ticks: { color: "#444" } }
        }
      }
    })

    // === Daily Chart ===
    this.dailyChart = new Chart(dailyCtx, {
      type: "line",
      data: {
        labels: Object.keys(this.dailyValue || {}),
        datasets: [{
          label: "Daily Requests",
          data: Object.values(this.dailyValue || {}),
          fill: true,
          borderColor: this.palmGreen,
          backgroundColor: "rgba(26,147,111,0.15)",
          pointBackgroundColor: this.palmGreen,
          pointRadius: 4,
          pointHoverRadius: 6,
          tension: 0.35
        }]
      },
      options: {
        responsive: true,
        animation: { duration: 800, easing: "easeInOutQuart" },
        plugins: {
          legend: { display: false },
          tooltip: {
            backgroundColor: this.palmGreen,
            titleColor: "#fff",
            bodyColor: "#fff",
            cornerRadius: 8
          }
        },
        scales: {
          x: { ticks: { color: "#555" } },
          y: { beginAtZero: true, grid: { color: "rgba(0,0,0,0.05)" } }
        }
      }
    })
  }

  async refreshData() {
    if (!this.hasRefreshUrlValue) return

    try {
      const response = await fetch(this.refreshUrlValue, {
        headers: { "Accept": "application/json" }
      })
      if (!response.ok) throw new Error("Failed to refresh chart data")
      const data = await response.json()

      this.endpointValue = data.calls_by_endpoint || {}
      this.dailyValue = data.calls_by_day || {}

      this.renderCharts()
      this.lastUpdatedAt = new Date()
      this.updateTimerText(true)
    } catch (err) {
      console.error("EmbassyCharts refresh error:", err)
    }
  }

  updateTimerText(refreshed = false) {
    if (!this.hasUpdatedLabelTarget || !this.hasTimerTarget) return

    const now = new Date()
    const secondsElapsed = Math.floor((now - this.lastUpdatedAt) / 1000)
    const timeString = secondsElapsed < 5
      ? "just now"
      : `${secondsElapsed}s ago`

    this.updatedLabelTarget.textContent = refreshed
      ? "Updated just now"
      : `Updated ${timeString}`
  }
}
