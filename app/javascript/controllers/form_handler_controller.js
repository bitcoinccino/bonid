import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "submit",
    "spinner",
    "submitText",
    "error",
    "fileInput",
    "imagePreview"
  ];

  connect() {
    console.log("FormHandlerController connected — BonID Ready", new Date().toLocaleString("en-HT"));
    this.clearError();
    this.submitTimeout = null;
    this.isSubmitting = false;
    this.submitStartTime = 0;
  }

  disconnect() {
    if (this.submitTimeout) clearTimeout(this.submitTimeout);
  }

  // ——————— FORM SUBMISSION ———————
  submitStart(event) {
    if (this.isSubmitting) {
      console.log("Submission blocked — already in progress");
      event?.preventDefault();
      return;
    }

    this.isSubmitting = true;
    this.submitStartTime = performance.now();

    if (this.hasSubmitTarget) this.submitTarget.disabled = true;
    if (this.hasSpinnerTarget) this.spinnerTarget.classList.remove("d-none");
    if (this.hasSubmitTextTarget) this.submitTextTarget.textContent = "Processing...";

    this.clearError();

    // 60-second timeout protection
    this.submitTimeout = setTimeout(() => {
      this._restoreSubmit();
      this.showError("Connection timeout. Please check your internet and try again.");
      this._notifyQrScanner("Timeout — please try again", "danger");
    }, 60_000);
  }

  submitEnd(event) {
    if (this.submitTimeout) clearTimeout(this.submitTimeout);
    const duration = Math.round(performance.now() - this.submitStartTime);

    const success = event.detail?.[2]?.status === 200 || event.detail?.[2]?.status === 302 || !event.detail;

    if (success) {
      this.showSuccess("Submitted successfully!");
      this._notifyQrScanner("Success", "success", true);
    } else {
      const msg = this._extractErrorMessage(event.detail?.[2]) || "Something went wrong. Please try again.";
      this.showError(msg);
      this._notifyQrScanner(msg, "danger");
    }

    this._restoreSubmit();
    console.log(`Form submission completed in ${duration}ms`);
  }

  submitError(event) {
    if (this.submitTimeout) clearTimeout(this.submitTimeout);

    const msg = this._extractErrorMessage(event.detail?.[2]) || "Network error. Please try again.";
    this.showError(msg);
    this._notifyQrScanner(msg, "danger");
    this._restoreSubmit();
  }

  // ——————— PHOTO PREVIEW ———————
  previewImage(event) {
    const file = event.target.files?.[0];
    if (!file) return;

    // Validate type
    if (!file.type.match(/^image\/(jpeg|png)$/i)) {
      this.showError("Please upload a JPEG or PNG image only.");
      event.target.value = "";
      return;
    }

    // Validate size (5MB)
    if (file.size > 5 * 1024 * 1024) {
      this.showError("Image too large. Maximum size is 5MB.");
      event.target.value = "";
      return;
    }

    const reader = new FileReader();
    reader.onload = (e) => {
      if (this.hasImagePreviewTarget) {
        this.imagePreviewTarget.src = e.target.result;
        this.imagePreviewTarget.classList.remove("d-none");

        // Hide placeholder if it exists
        const wrapper = this.imagePreviewTarget.closest(".profile-photo-wrapper") || this.imagePreviewTarget.closest(".photo-upload-wrapper");
        const placeholder = wrapper?.querySelector(".photo-placeholder");
        if (placeholder) placeholder.classList.add("d-none");
      }
    };
    reader.readAsDataURL(file);
  }

  // ——————— UTILITIES ———————
  _restoreSubmit() {
    this.isSubmitting = false;
    if (this.hasSubmitTarget) this.submitTarget.disabled = false;
    if (this.hasSpinnerTarget) this.spinnerTarget.classList.add("d-none");
    if (this.hasSubmitTextTarget) {
      this.submitTextTarget.textContent = this.element.closest("#bonidScanModal") ? "Submit" : "Continue";
    }
  }

  clearError() {
    if (this.hasErrorTarget) {
      this.errorTarget.classList.add("d-none");
      this.errorTarget.textContent = "";
    }
  }

  showError(message) {
    if (this.hasErrorTarget) {
      this.errorTarget.className = "alert alert-danger small text-center mt-3";
      this.errorTarget.textContent = message;
      this.errorTarget.classList.remove("d-none");
    }
  }

  showSuccess(message) {
    if (this.hasErrorTarget) {
      this.errorTarget.className = "alert alert-success small text-center mt-3";
      this.errorTarget.textContent = message;
      this.errorTarget.classList.remove("d-none");
    }
  }

  _extractErrorMessage(xhr) {
    if (!xhr?.response) return null;
    try {
      const doc = new DOMParser().parseFromString(xhr.response, "text/html");
      const alert = doc.querySelector(".alert-danger, .alert-warning");
      return alert?.textContent.trim() || null;
    } catch {
      return null;
    }
  }

  _notifyQrScanner(message, type, autoHide = false) {
    const modal = document.getElementById("bonidScanModal");
    const scanner = modal?.__vue__ || this.application.getControllerForElementAndIdentifier(modal, "qr-scanner");
    if (scanner) {
      scanner.setOutput?.(message, type);
      scanner.showResult?.();
      if (type === "danger") scanner.playErrorSound?.();
      if (type === "success") scanner.playSuccessSound?.();
      if (autoHide) setTimeout(() => bootstrap.Modal.getInstance(modal)?.hide(), 2000);
    }
  }
}