// app/javascript/controllers/sector_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "sectorSelect",
    "unitTypeWrapper",
    "unitNameWrapper",
    "unitTypeSelect",
    "unitNameSelect",
    "useCaseSelect",
    "useCaseWrapper",
    "otherUseCaseWrapper",
    "otherUseCaseInput",
    "additionalFieldsWrapper",
    "addressWrapper",
    "countryWrapper",
    "countrySelect",
    "pnhNotice"
  ];

  connect() {
    console.log("📌 SectorController connected");

    this.unitOptions = this.loadUnitOptions();
    this.useCaseOptions = this.loadUseCaseOptions();
    this.countryRequiredSectors = this.loadCountryRequiredSectors();

    // Only run if targets exist
    if (this.hasSectorSelectTarget) {
      this.toggleUnitFields();
    }

    if (this.hasUseCaseSelectTarget) {
      this.populateUseCases();
    }

    this.populateUnitNamesOnEdit();
  }

  // ----------------------------------------
  // SHOW/HIDE FIELDS BASED ON SECTOR
  // ----------------------------------------
  toggleUnitFields() {
    if (!this.hasSectorSelectTarget) return;

    const value = this.sectorSelectTarget.value;
    const isPNH = value === "pnh";

    console.log(`🔄 Toggling fields for sector: ${value}, isPNH: ${isPNH}`);

    // Show/hide PNH unit fields
    if (this.hasUnitTypeWrapperTarget) {
      this.unitTypeWrapperTarget.classList.toggle("d-none", !isPNH);
    }
    if (this.hasUnitNameWrapperTarget) {
      this.unitNameWrapperTarget.classList.toggle("d-none", !isPNH);
    }

    // Show/hide description & website (hide for PNH)
    if (this.hasAdditionalFieldsWrapperTarget) {
      this.additionalFieldsWrapperTarget.classList.toggle("d-none", isPNH);
    }

    // Show/hide address (hide for PNH)
    if (this.hasAddressWrapperTarget) {
      this.addressWrapperTarget.classList.toggle("d-none", isPNH);
    }

    // Show/hide use cases (hide for PNH)
    if (this.hasUseCaseWrapperTarget) {
      this.useCaseWrapperTarget.classList.toggle("d-none", isPNH);
    }

    // Show/hide PNH notice
    if (this.hasPnhNoticeTarget) {
      this.pnhNoticeTarget.classList.toggle("d-none", !isPNH);
    }

    // Clear unit fields when not PNH
    if (!isPNH && this.hasUnitTypeSelectTarget && this.hasUnitNameSelectTarget) {
      this.unitTypeSelectTarget.value = "";
      this.unitNameSelectTarget.innerHTML = '<option value="">Select Unit Name</option>';
    }

    // Show/hide country field for embassy/consulate/international sectors
    const needsCountry = this.countryRequiredSectors.includes(value);
    if (this.hasCountryWrapperTarget) {
      this.countryWrapperTarget.classList.toggle("d-none", !needsCountry);
    }
    if (!needsCountry && this.hasCountrySelectTarget) {
      this.countrySelectTarget.value = "";
    }
  }

  // ----------------------------------------
  // POPULATE UNIT NAMES WHEN UNIT TYPE CHANGES
  // ----------------------------------------
  populateUnitNames(event) {
    if (!this.hasUnitTypeSelectTarget || !this.hasUnitNameSelectTarget) return;

    const selectedUnitType = event?.target?.value || this.unitTypeSelectTarget.value;

    console.log(`📝 Populating unit names for: ${selectedUnitType}`);

    const names = this.unitOptions[selectedUnitType] || [];

    this.unitNameSelectTarget.innerHTML = '<option value="">Select Unit Name</option>';

    names.forEach((name) => {
      const opt = document.createElement("option");
      opt.value = name;
      opt.textContent = name;
      this.unitNameSelectTarget.appendChild(opt);
    });

    const saved = this.unitNameSelectTarget.dataset.selected;
    if (saved) this.unitNameSelectTarget.value = saved;

    console.log(`✅ Populated ${names.length} unit names`);
  }

  // ----------------------------------------
  // POPULATE USE CASES BASED ON SECTOR
  // ----------------------------------------
  populateUseCases() {
    if (!this.hasSectorSelectTarget || !this.hasUseCaseSelectTarget) return;

    const sector = this.sectorSelectTarget.value;
    const useCases = this.useCaseOptions[sector] || this.useCaseOptions["default"];

    // Reset options
    this.useCaseSelectTarget.innerHTML = '<option value="">Select a use case</option>';

    // Fill dropdown
    useCases.forEach((uc) => {
      const opt = document.createElement("option");
      opt.value = uc;
      opt.textContent = uc;
      this.useCaseSelectTarget.appendChild(opt);
    });
  }

  // ----------------------------------------
  // SHOW "OTHER" FIELD WHEN SELECTED
  // ----------------------------------------
  showOrHideOtherUseCase(event) {
    if (!this.hasOtherUseCaseWrapperTarget || !this.hasOtherUseCaseInputTarget) return;

    // Get all selected values from the multi-select
    const selectedOptions = Array.from(event.target.selectedOptions).map(opt => opt.value);
    const isOther = selectedOptions.includes("Other");

    this.otherUseCaseWrapperTarget.classList.toggle("d-none", !isOther);

    if (!isOther) this.otherUseCaseInputTarget.value = "";
  }

  // ----------------------------------------
  // LOAD JSON OPTIONS
  // ----------------------------------------
  loadUnitOptions() {
    const script = document.getElementById("unit-options-json");
    if (!script) {
      console.warn("⚠️ unit-options-json not found");
      return {};
    }
    return JSON.parse(script.textContent);
  }

  loadUseCaseOptions() {
    const script = document.getElementById("use-cases-json");
    if (!script) {
      console.warn("⚠️ use-cases-json not found");
      return {};
    }
    return JSON.parse(script.textContent);
  }

  loadCountryRequiredSectors() {
    const script = document.getElementById("country-required-sectors-json");
    if (!script) {
      console.warn("⚠️ country-required-sectors-json not found");
      return [];
    }
    return JSON.parse(script.textContent);
  }

  // ----------------------------------------
  // POPULATE ON EDIT LOAD
  // ----------------------------------------
  populateUnitNamesOnEdit() {
    if (!this.hasSectorSelectTarget || !this.hasUnitTypeSelectTarget) return;

    if (this.sectorSelectTarget.value === "pnh" && this.unitTypeSelectTarget.value) {
      this.populateUnitNames();
    }
  }
}
