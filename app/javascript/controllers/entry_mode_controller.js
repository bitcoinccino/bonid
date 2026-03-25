// app/javascript/controllers/entry_mode_controller.js

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["entryMode", "port", "transport"]

  connect() {
    this.updateOptions()
  }

  updateOptions() {
    const mode = this.entryModeTarget.value
    const portSelect = this.portTarget
    const transportSelect = this.transportTarget

    if (!mode) {
      // Reset to prompt if no mode selected
      portSelect.innerHTML = '<option value="">Select entry mode first</option>'
      transportSelect.innerHTML = '<option value="">Select entry mode first</option>'
      return
    }

    const portsByMode = {
      air: [
        { label: "Toussaint Louverture International Airport (PAP)", value: "PAP" },
        { label: "Cap-Haïtien International Airport (CAP)", value: "CAP" },
        { label: "Antoine-Simon Airport (CYA - Les Cayes)", value: "CYA" },
        { label: "Jérémie Airport (JEE)", value: "JEE" },
        { label: "Jacmel Airport (JAK)", value: "JAK" }
      ],
      sea: [
        { label: "Labadee Cruise Port", value: "LAB" },
        { label: "Port of Miragoâne", value: "MIR" },
        { label: "Port of Jacmel", value: "JAC" },
        { label: "Port of Cap-Haïtien", value: "PCH" }
      ],
      land: [
        { label: "Malpasse – Jimaní", value: "MAL" },
        { label: "Ouanaminthe – Dajabón", value: "OUA" },
        { label: "Anse-à-Pitres – Pedernales", value: "ANP" },
        { label: "Belladère – Comendador", value: "BEL" }
      ]
    }

    const transportByMode = {
      air: [
        "American Airlines",
        "Spirit Airlines",
        "JetBlue Airways",
        "Air Canada",
        "Air France",
        "Sunrise Airways",
        "Winair"
      ],
      sea: [
        "Royal Caribbean Cruises",
        "Carnival Cruise Lines",
        "Private Yacht / Charter"
      ],
      land: [
        "Border Bus",
        "Private Car",
        "Commercial Truck",
        "Taxi Service"
      ]
    }

    // Update ports
    portSelect.innerHTML = '<option value="">Select port</option>'
    const ports = portsByMode[mode] || []
    ports.forEach(({ label, value }) => {
      const option = document.createElement("option")
      option.value = value
      option.textContent = label
      portSelect.appendChild(option)
    })

    // Update transport
    transportSelect.innerHTML = '<option value="">Select provider</option>'
    const transports = transportByMode[mode] || []
    transports.forEach(name => {
      const option = document.createElement("option")
      option.value = name
      option.textContent = name
      transportSelect.appendChild(option)
    })
  }
}