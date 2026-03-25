import { Controller } from "@hotwired/stimulus"

// Wallet Stack Controller
// Handles Apple Wallet-style card stacking behind BonID
export default class extends Controller {
  static targets = ["card"]

  connect() {
    this.activeCard = "bonid"
    this.initializeStack()
  }

  initializeStack() {
    // Set initial state - BonID active, others stacked behind
    this.cardTargets.forEach(card => {
      const type = card.dataset.card
      if (type === "bonid") {
        card.classList.add("active")
        card.classList.remove("stacked", "pushed-back")
      } else {
        card.classList.add("stacked")
        card.classList.remove("active", "pushed-back")
      }
    })
  }

  showCard(event) {
    const cardType = event.currentTarget.dataset.cardType
    this.switchToCard(cardType)
  }

  showBonid() {
    this.switchToCard("bonid")
  }

  switchToCard(cardType) {
    if (this.activeCard === cardType) return

    this.cardTargets.forEach(card => {
      const type = card.dataset.card

      if (type === cardType) {
        // Bring this card to front
        card.classList.remove("stacked", "pushed-back")
        card.classList.add("active")
      } else if (type === "bonid" && cardType !== "bonid") {
        // Push BonID back when showing another card
        card.classList.remove("active", "stacked")
        card.classList.add("pushed-back")
      } else {
        // Other cards stay stacked
        card.classList.remove("active", "pushed-back")
        card.classList.add("stacked")
      }
    })

    this.activeCard = cardType
  }
}
