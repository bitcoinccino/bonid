import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["sectorSelect", "unitNameWrapper", "unitTypeWrapper"];

  connect() {
    console.log("📌 SectorController connected");
    this.toggleUnitFields();
  }

  toggleUnitFields() {
    const selectedValue = this.sectorSelectTarget.value;
    console.log("Selected sector:", selectedValue);

    const isLaw = selectedValue === "law_enforcement";

    this.unitNameWrapperTarget.classList.toggle("d-none", !isLaw);
    this.unitTypeWrapperTarget.classList.toggle("d-none", !isLaw);
  }
}  

