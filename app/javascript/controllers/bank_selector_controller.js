// app/javascript/controllers/bank_selector_controller.js
import { Controller } from "@hotwired/stimulus"

// Handles toggling bank/mobile wallet/crypto wallet fields dynamically based on account_source
export default class extends Controller {
  static targets = [
    "bankFields",        // Fields for traditional bank accounts
    "mobileWalletFields", // Fields for mobile wallets (MonCash, NatCash)
    "cryptoWalletFields", // Fields for crypto wallets (Phantom, Coinbase)
    "accountTypeField",   // Account type (checking/savings) - only for banks
    "swift"              // SWIFT code field
  ]

  connect() {
    // Small delay to ensure DOM is fully rendered after template insertion
    requestAnimationFrame(() => this.toggleFieldsOnLoad())
  }

  toggleBankFields(event) {
    const value = event?.target?.value || ""
    this.showRelevantFields(value)
  }

  toggleFieldsOnLoad() {
    const selector = this.element.querySelector('[name*="[account_source]"]')
    if (selector && selector.value) {
      // Only show fields if a value is already selected (for existing records)
      this.showRelevantFields(selector.value)
    }
    // If no value, all fields stay hidden (default state for new records)
  }

  showRelevantFields(value) {
    const isBank = value === "bank"
    const isMobileWallet = value === "mobile_wallet"
    const isCryptoWallet = value === "crypto_wallet"

    // Helper to toggle field visibility and disable hidden fields
    const toggleFields = (targets, show) => {
      targets.forEach((el) => {
        el.classList.toggle("d-none", !show)
        el.querySelectorAll("input, select").forEach(input => {
          if (!show) {
            input.removeAttribute("required")
            input.value = ""
            input.disabled = true  // Prevent submission of hidden fields
          } else {
            input.disabled = false  // Re-enable visible fields
          }
        })
      })
    }

    // Bank fields: bank_name, branch_name, account_number, account_type
    toggleFields(this.bankFieldsTargets, isBank)

    // Account type dropdown (checking/savings/business) - only for banks
    toggleFields(this.accountTypeFieldTargets, isBank)

    // Mobile wallet fields: provider dropdown, phone number
    toggleFields(this.mobileWalletFieldsTargets, isMobileWallet)

    // Crypto wallet fields: provider, chain, wallet address
    toggleFields(this.cryptoWalletFieldsTargets, isCryptoWallet)
  }

  async updateSwift(event) {
    const bankName = event.target.value?.trim()
    if (!bankName) return this.clearSwift()

    try {
      const response = await fetch(`/banks/swift_lookup?name=${encodeURIComponent(bankName)}`)
      const data = await response.json()
      if (data.swift_code) {
        this.swiftTargets.forEach((el) => {
          el.value = data.swift_code
          el.classList.add("border-success")
          setTimeout(() => el.classList.remove("border-success"), 800)
        })
      } else {
        this.clearSwift()
      }
    } catch (error) {
      console.error("❌ [BankSelectorController] SWIFT lookup failed:", error)
      this.clearSwift()
    }
  }

  clearSwift() {
    this.swiftTargets.forEach((el) => (el.value = ""))
  }
}
