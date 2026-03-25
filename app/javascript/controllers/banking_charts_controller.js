import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"
Chart.register(...registerables)

export default class extends Controller {
  static values = {
    refreshUrl: String,
    kyc: Object,
    transactions: Object,
    financial: Object,
    qrscans: Object
  }

  static targets = [
    "updatedLabel",
    "timer",
    "depositsCounter",
    "withdrawalsCounter",
    "approvalRatioCounter"
  ]

  // Chart instances — must be declared so destroy() works properly
  kycChart = null
  transactionsChart = null
  scanChart = null
  tellerChart = null
  branchChart = null
  departmentChart = null

  connect() {
    // BonID Haitian Color Palette
    this.colors = {
      haitianBlue: "#04328C",
      palmGreen: "#1A936F",
      gold: "#FFD700",
      coral: "#ED8936",
      red: "#E53E3E"
    }

    this.lastUpdatedAt = new Date()
    this.updateTimerText()
    this.renderAllCharts()
    this.updateFinancialCounters(this.financialValue || {})
    this.updateScanSummary()

    // Auto-refresh every 30 seconds
    this.refreshInterval = setInterval(() => this.refreshData(), 30000)
    this.timerInterval = setInterval(() => this.updateTimerText(), 1000)
  }

  disconnect() {
    clearInterval(this.refreshInterval)
    clearInterval(this.timerInterval)
    this.destroyCharts()
  }

  // Render ALL charts in correct order
  renderAllCharts() {
    this.destroyCharts()
    this.renderKycChart()
    this.renderTransactionsChart()
    this.renderScanChart()
    this.renderTellerChart()
    this.renderBranchChart()
    this.renderDepartmentChart()
  }

  // Destroy ALL chart instances safely
  destroyCharts() {
    ;[this.kycChart, this.transactionsChart, this.scanChart, this.tellerChart, this.branchChart, this.departmentChart]
      .forEach(chart => chart?.destroy())
  }

  // KYC Verifications Over Time (Line Chart)
  renderKycChart() {
    const ctx = this.element.querySelector("#kycChart")
    if (!ctx || !Object.keys(this.kycValue || {}).length) return

    this.kycChart = new Chart(ctx, {
      type: "line",
      data: {
        labels: Object.keys(this.kycValue),
        datasets: [{
          label: "KYC Verifications",
          data: Object.values(this.kycValue),
          borderColor: this.colors.palmGreen,
          backgroundColor: "rgba(26,147,111,0.15)",
          pointBackgroundColor: this.colors.palmGreen,
          pointRadius: 4,
          tension: 0.35,
          fill: true
        }]
      },
      options: {
        plugins: { legend: { display: false } },
        scales: {
          y: { beginAtZero: true, grid: { color: "rgba(0,0,0,0.05)" } },
          x: { ticks: { color: "#444" } }
        }
      }
    })
  }

  // Transactions by Type (Pie Chart)
  renderTransactionsChart() {
    const ctx = this.element.querySelector("#transactionsChart")
    if (!ctx || !Object.keys(this.transactionsValue || {}).length) return

    this.transactionsChart = new Chart(ctx, {
      type: "pie",
      data: {
        labels: Object.keys(this.transactionsValue),
        datasets: [{
          label: "Transactions by Type",
          data: Object.values(this.transactionsValue),
          backgroundColor: [
            this.colors.haitianBlue,
            this.colors.palmGreen,
            this.colors.gold,
            this.colors.red,
            this.colors.coral
          ],
          borderWidth: 1
        }]
      },
      options: {
        plugins: { legend: { position: "bottom" } }
      }
    })
  }

  // QR Scans vs Manual Entries (Dual Line Chart)
  renderScanChart() {
    const ctx = this.element.querySelector("#scanChart")
    if (!ctx || !this.qrscansValue) return

    const scanned = this.qrscansValue.scanned || {}
    const manual = this.qrscansValue.manual || {}
    const allLabels = Array.from(new Set([...Object.keys(scanned), ...Object.keys(manual)])).sort()

    this.scanChart = new Chart(ctx, {
      type: "line",
      data: {
        labels: allLabels,
        datasets: [
          {
            label: "Scanned IDs",
            data: allLabels.map(date => scanned[date] || 0),
            borderColor: this.colors.haitianBlue,
            backgroundColor: "rgba(4,50,140,0.25)",
            fill: true,
            tension: 0.35
          },
          {
            label: "Manual Entries",
            data: allLabels.map(date => manual[date] || 0),
            borderColor: this.colors.red,
            backgroundColor: "rgba(229,62,62,0.25)",
            fill: true,
            tension: 0.35
          }
        ]
      },
      options: {
        responsive: true,
        interaction: { mode: "index", intersect: false },
        plugins: { legend: { position: "bottom" } },
        scales: {
          y: { beginAtZero: true, title: { display: true, text: "Entries per Day" } },
          x: { title: { display: true, text: "Date" } }
        }
      }
    })
  }

  // Top 5 Tellers (Pie Chart)
  renderTellerChart() {
    const ctx = this.element.querySelector("#tellerChart")
    if (!ctx || !this.qrscansValue?.tellers) return

    const top = Object.entries(this.qrscansValue.tellers)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)

    const labels = top.map(([email]) => email.split("@")[0])
    const values = top.map(([_, count]) => count)

    this.tellerChart = new Chart(ctx, {
      type: "pie",
      data: {
        labels,
        datasets: [{
          data: values,
          backgroundColor: [
            this.colors.haitianBlue,
            this.colors.palmGreen,
            this.colors.gold,
            this.colors.coral,
            this.colors.red
          ]
        }]
      },
      options: {
        plugins: {
          legend: { position: "bottom" },
          tooltip: {
            callbacks: {
              label: (t) => `${labels[t.dataIndex]}: ${values[t.dataIndex]} scans`
            }
          }
        }
      }
    })
  }

  // Branch Performance (Vertical Bar Chart)
  renderBranchChart() {
    const ctx = this.element.querySelector("#branchChart")
    if (!ctx || !this.qrscansValue?.branches) return

    const labels = Object.keys(this.qrscansValue.branches)
    const values = Object.values(this.qrscansValue.branches)

    this.branchChart = new Chart(ctx, {
      type: "bar",
      data: {
        labels,
        datasets: [{
          label: "Scans per Branch",
          data: values,
          backgroundColor: this.colors.haitianBlue,
          borderRadius: 6
        }]
      },
      options: {
        plugins: { legend: { display: false } },
        scales: {
          y: { beginAtZero: true, title: { display: true, text: "Total Scans" }, grid: { color: "rgba(0,0,0,0.05)" } },
          x: { title: { display: true, text: "Branch" }, ticks: { maxRotation: 45, minRotation: 0 } }
        }
      }
    })
  }

  // Department Performance (Horizontal Bar Chart)
  renderDepartmentChart() {
    const ctx = this.element.querySelector("#departmentChart")
    if (!ctx || !this.qrscansValue?.departments) return

    const labels = Object.keys(this.qrscansValue.departments)
    const values = Object.values(this.qrscansValue.departments)

    this.departmentChart = new Chart(ctx, {
      type: "bar",
      data: {
        labels,
        datasets: [{
          label: "Scans per Department",
          data: values,
          backgroundColor: this.colors.palmGreen,
          borderRadius: 6
        }]
      },
      options: {
        indexAxis: "y",
        plugins: { legend: { display: false } },
        scales: {
          x: { beginAtZero: true, title: { display: true, text: "Total Scans" } },
          y: { title: { display: true, text: "Department" }, ticks: { color: "#444" } }
        }
      }
    })
  }

  // Mini Summary Below Charts
  updateScanSummary() {
    const summaryEl = document.getElementById("scan-summary")
    if (!summaryEl || !this.qrscansValue) return

    const scannedTotal = Object.values(this.qrscansValue.scanned || {}).reduce((a, b) => a + b, 0)
    const manualTotal = Object.values(this.qrscansValue.manual || {}).reduce((a, b) => a + b, 0)
    const tellerCount = Object.keys(this.qrscansValue.tellers || {}).length || 0
    const branchCount = this.qrscansValue.branches ? Object.keys(this.qrscansValue.branches).length : 0

    summaryEl.innerHTML = `
      <div class="small text-muted text-center mt-2">
        <span class="fw-semibold text-primary">${scannedTotal.toLocaleString()}</span> Scanned •
        <span class="fw-semibold text-danger">${manualTotal.toLocaleString()}</span> Manual •
        <span class="fw-semibold text-success">${branchCount}</span> Branches •
        <span class="fw-semibold text-warning">${tellerCount}</span> Tellers
      </div>
    `
  }

  // Refresh data from JSON endpoint
  async refreshData() {
    if (!this.hasRefreshUrlValue) return
    try {
      const res = await fetch(this.refreshUrlValue, { headers: { Accept: "application/json" } })
      const data = await res.json()

      this.kycValue = data.kyc_verifications_by_day || {}
      this.transactionsValue = data.transactions_by_type || {}
      this.financialValue = data.financial || {}
      this.qrscansValue = data.qr_scans || {}

      this.renderAllCharts()
      this.updateFinancialCounters(this.financialValue)
      this.updateScanSummary()

      this.lastUpdatedAt = new Date()
      this.flashUpdatedLabel()
    } catch (err) {
      console.error("Dashboard refresh error:", err)
    }
  }

  flashUpdatedLabel() {
    if (!this.hasUpdatedLabelTarget) return
    this.updatedLabelTarget.classList.add("flash")
    setTimeout(() => this.updatedLabelTarget.classList.remove("flash"), 600)
  }

  updateTimerText() {
    if (!this.hasUpdatedLabelTarget || !this.hasTimerTarget) return
    const seconds = Math.floor((new Date() - this.lastUpdatedAt) / 1000)
    this.updatedLabelTarget.textContent =
      seconds < 5 ? "Updated just now" : `Updated ${seconds}s ago`
  }

  updateFinancialCounters(financial) {
    if (!financial) return
    const { deposits, withdrawals, approval_ratio } = financial

    if (this.hasDepositsCounterTarget)
      this.animateCounter(this.depositsCounterTarget, deposits || 0)
    if (this.hasWithdrawalsCounterTarget)
      this.animateCounter(this.withdrawalsCounterTarget, withdrawals || 0)
    if (this.hasApprovalRatioCounterTarget)
      this.animateCounter(this.approvalRatioCounterTarget, approval_ratio || 0, true)
  }

  animateCounter(el, value, isPercent = false) {
    if (!el) return
    const start = parseFloat(el.textContent.replace(/[^0-9.-]/g, "")) || 0
    const end = parseFloat(value)
    const duration = 800
    const startTime = performance.now()

    const animate = (time) => {
      const progress = Math.min((time - startTime) / duration, 1)
      const current = start + (end - start) * progress
      el.textContent = isPercent
        ? `${current.toFixed(1)}%`
        : Math.round(current).toLocaleString()
      if (progress < 1) requestAnimationFrame(animate)
    }
    requestAnimationFrame(animate)
  }
}