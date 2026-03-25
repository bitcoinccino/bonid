import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["step", "progressBar"];

  connect() { this.updateProgress(); }

  nextStep(event) {
    event.preventDefault();
    const current = this.stepTargets.find(s => s.classList.contains("active"));
    if (!this.validateStep(current)) return;
    const next = this.stepTargets[this.stepTargets.indexOf(current)+1];
    if (next) {
      current.classList.remove("active"); current.classList.add("d-none");
      next.classList.remove("d-none"); next.classList.add("active");
      this.updateProgress();
    }
  }

  prevStep(event) {
    event.preventDefault();
    const current = this.stepTargets.find(s => s.classList.contains("active"));
    const prev = this.stepTargets[this.stepTargets.indexOf(current)-1];
    if (prev) {
      current.classList.remove("active"); current.classList.add("d-none");
      prev.classList.remove("d-none"); prev.classList.add("active");
      this.updateProgress();
    }
  }

  updateProgress() {
    const idx = this.stepTargets.findIndex(s => s.classList.contains("active"));
    if (this.hasProgressBarTarget)
      this.progressBarTarget.style.width = `${((idx+1)/this.stepTargets.length)*100}%`;
  }

  validateStep(step) {
    const required = step.querySelectorAll("input[required], select[required], textarea[required]");
    let valid = true;
    required.forEach(i => {
      i.classList.remove("is-invalid");
      if (!i.value.trim()) { i.classList.add("is-invalid"); valid=false; }
    });
    if (!valid) this.showAlert("Please complete all required fields before continuing.");
    return valid;
  }

  showAlert(msg) {
    const active = this.stepTargets.find(s => s.classList.contains("active"));
    active.querySelectorAll(".alert").forEach(a => a.remove());
    const alert = document.createElement("div");
    alert.className = "alert alert-warning mt-3"; alert.textContent = msg;
    active.prepend(alert);
    setTimeout(()=>alert.remove(),3000);
  }
}
