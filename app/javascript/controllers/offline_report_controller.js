import { Controller } from "@hotwired/stimulus"

// Handles offline saving and auto-sync for incident reports
// When offline: saves form data to localStorage
// When online: auto-syncs pending reports
export default class extends Controller {
  static targets = ["form", "offlineIndicator", "pendingAlert", "pendingCount"]

  connect() {
    console.log("📴 OfflineReportController connected")
    this.checkPendingReports()
    this.setupConnectivityListeners()
    this.updateOnlineStatus()
  }

  // Check online status and update UI
  updateOnlineStatus() {
    if (!navigator.onLine) {
      this.showOfflineIndicator()
    } else {
      this.hideOfflineIndicator()
      this.syncPendingReports()
    }
  }

  // Intercept form submit when offline
  handleSubmit(event) {
    if (!navigator.onLine) {
      event.preventDefault()
      this.saveOffline()
    }
    // If online, let form submit normally
  }

  // Save form data to localStorage
  saveOffline() {
    if (!this.hasFormTarget) {
      console.error("No form target found")
      return
    }

    const formData = new FormData(this.formTarget)
    const report = {}

    // Convert FormData to object, handling nested attributes
    for (const [key, value] of formData.entries()) {
      report[key] = value
    }

    report._savedAt = new Date().toISOString()
    report._syncStatus = 'pending'
    report._officerId = this.formTarget.dataset.officerId || 'unknown'

    this.addToPendingReports(report)
    this.showSavedAlert()
    this.checkPendingReports()
  }

  // Sync pending reports when back online
  async syncPendingReports() {
    const pending = this.getPendingReports()
    if (pending.length === 0) return

    console.log(`🔄 Syncing ${pending.length} pending report(s)...`)

    for (const report of pending) {
      try {
        const formData = new FormData()

        // Reconstruct FormData from saved object
        for (const [key, value] of Object.entries(report)) {
          if (!key.startsWith('_')) { // Skip internal keys
            formData.append(key, value)
          }
        }

        const response = await fetch('/officers/incident_reports', {
          method: 'POST',
          headers: {
            'X-CSRF-Token': this.getCsrfToken()
          },
          body: formData
        })

        if (response.ok || response.redirected) {
          this.removeFromPending(report._savedAt)
          console.log(`✅ Report synced successfully`)
          this.showSyncSuccess()
        } else {
          console.error(`❌ Sync failed with status ${response.status}`)
        }
      } catch (error) {
        console.error('Sync failed:', error)
      }
    }

    this.checkPendingReports()
  }

  // Set up connectivity event listeners
  setupConnectivityListeners() {
    window.addEventListener('online', () => {
      console.log("🌐 Connection restored")
      this.hideOfflineIndicator()
      this.syncPendingReports()
    })

    window.addEventListener('offline', () => {
      console.log("📴 Connection lost")
      this.showOfflineIndicator()
    })
  }

  // UI Helpers
  showOfflineIndicator() {
    if (this.hasOfflineIndicatorTarget) {
      this.offlineIndicatorTarget.classList.remove('d-none')
    }
  }

  hideOfflineIndicator() {
    if (this.hasOfflineIndicatorTarget) {
      this.offlineIndicatorTarget.classList.add('d-none')
    }
  }

  showSavedAlert() {
    // Create a more user-friendly notification
    const message = 'You are offline. Your report has been saved locally and will be submitted automatically when connectivity returns.'

    // Try using toast if available, otherwise alert
    if (typeof Toastify !== 'undefined') {
      Toastify({
        text: message,
        duration: 5000,
        gravity: "top",
        position: "center",
        backgroundColor: "#ffc107"
      }).showToast()
    } else {
      alert(message)
    }
  }

  showSyncSuccess() {
    const message = 'Your offline report has been submitted successfully!'

    if (typeof Toastify !== 'undefined') {
      Toastify({
        text: message,
        duration: 3000,
        gravity: "top",
        position: "center",
        backgroundColor: "#28a745"
      }).showToast()
    }

    // Optionally reload to show the new report
    // window.location.reload()
  }

  checkPendingReports() {
    const pending = this.getPendingReports()

    if (this.hasPendingAlertTarget && this.hasPendingCountTarget) {
      if (pending.length > 0) {
        this.pendingAlertTarget.classList.remove('d-none')
        this.pendingCountTarget.textContent = pending.length
      } else {
        this.pendingAlertTarget.classList.add('d-none')
      }
    }
  }

  // LocalStorage Helpers
  getPendingReports() {
    try {
      return JSON.parse(localStorage.getItem('pendingIncidentReports') || '[]')
    } catch (e) {
      console.error('Failed to parse pending reports:', e)
      return []
    }
  }

  addToPendingReports(report) {
    const pending = this.getPendingReports()
    pending.push(report)
    localStorage.setItem('pendingIncidentReports', JSON.stringify(pending))
    console.log(`💾 Report saved to localStorage (${pending.length} pending)`)
  }

  removeFromPending(savedAt) {
    const pending = this.getPendingReports().filter(r => r._savedAt !== savedAt)
    localStorage.setItem('pendingIncidentReports', JSON.stringify(pending))
  }

  getCsrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ''
  }

  // Manual sync trigger (from UI button)
  manualSync() {
    if (navigator.onLine) {
      this.syncPendingReports()
    } else {
      alert('You are still offline. Please wait for connectivity to return.')
    }
  }
}
