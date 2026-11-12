// app/javascript/controllers/profile_review_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "reviewPhoto",
    "reviewPersonal",
    "reviewIdentification",
    "reviewAddress"
  ]

  // Localized copy from the page (citizen's portal language). Each label
  // falls back to English so the controller still works without them.
  //   labels: { full_name: "Non konplè", ..., date_format: "{day} {month} {year}" }
  //   months: ["", "janvye", ...]  (1-based, index 0 unused)
  static values = { labels: Object, months: Array }

  _l(key, fallback) {
    return (this.hasLabelsValue && this.labelsValue[key]) || fallback
  }

  connect() {
    // Listen for step changes on the same element
    this.element.addEventListener("wizard:stepChanged", this._onStep.bind(this))
  }

  // Direct event listener (more reliable than data-action for custom events)
  _onStep(event) {
    const step = event.detail?.step
    const totalSteps = this.element.querySelectorAll("[data-wizard-target='step']").length
    if (step === totalSteps) {
      this._populateFromForm()
    }
  }

  // Also callable via data-action as fallback
  onStepChanged(event) {
    this._onStep(event)
  }

  _populateFromForm() {
    const el = this.element

    // ── Photo ──
    if (this.hasReviewPhotoTarget) {
      const photoInput = el.querySelector("input[type='file'][name='user[photo]']")
      const hasNew = photoInput?.files?.length > 0
      const hasExisting = !!el.querySelector("img.photo-preview:not(.d-none)")

      const imgStyle = "width: 96px; height: 96px; border-radius: 50%; object-fit: cover; border: 2px solid #e4e7ec;"
      if (hasNew) {
        const file = photoInput.files[0]
        const url = URL.createObjectURL(file)
        this.reviewPhotoTarget.classList.add("text-center")
        this.reviewPhotoTarget.innerHTML = `
          <img src="${url}" alt="${this._esc(this._l("photo_preview", "Photo preview"))}" class="d-block mx-auto mb-2" style="${imgStyle}">
          <span class="text-success"><i class="ri-checkbox-circle-line me-1"></i>${this._esc(this._l("new_photo", "New photo selected"))}</span>`
      } else if (hasExisting) {
        const existingImg = el.querySelector("img.photo-preview:not(.d-none)")
        const src = existingImg ? existingImg.src : ""
        this.reviewPhotoTarget.classList.add("text-center")
        this.reviewPhotoTarget.innerHTML = `
          ${src ? `<img src="${src}" alt="${this._esc(this._l("photo_preview", "Photo preview"))}" class="d-block mx-auto mb-2" style="${imgStyle}">` : ""}
          <span class="text-success"><i class="ri-checkbox-circle-line me-1"></i>${this._esc(this._l("photo_uploaded", "Photo uploaded"))}</span>`
      }
      // If neither, keep server-rendered default
    }

    // ── Personal ──
    if (this.hasReviewPersonalTarget) {
      const prefix     = this._sel(el, "user[prefix]")
      const firstName  = this._val(el, "user[first_name]")
      const middleName = this._val(el, "user[middle_name]")
      const suffix     = this._sel(el, "user[suffix]")
      const lastName   = this._val(el, "user[last_name]")
      const sex        = this._sel(el, "user[sex]")
      const nationality = this._val(el, "user[nationality]")
      const phone      = this._val(el, "user[phone]")
      const marital    = this._sel(el, "user[marital_status]")
      const dob        = this._date(el, "user[dob]")

      const fullName = [prefix, firstName, middleName, lastName, suffix].filter(Boolean).join(" ")

      // Only overwrite if at least one field has a value
      if (fullName || sex || dob || phone) {
        // Resolve each cell: form value first, then fall back to whatever the
        // server already rendered (handles locked fields that the form can't
        // round-trip — e.g. the verified-state DOB <input type="text"> has no
        // name attribute, so its value never reaches the JS).
        const t = this.reviewPersonalTarget
        this.reviewPersonalTarget.innerHTML = [
          this._row(t, "full_name", "Full Name", fullName),
          this._row(t, "sex", "Sex", sex),
          this._row(t, "dob", "Date of Birth", dob),
          this._row(t, "nationality", "Nationality", nationality),
          this._row(t, "phone", "Phone", phone, this._carrier(phone)),
          this._row(t, "marital_status", "Marital Status", marital)
        ].join("")
      }
    }

    // ── Identification ──
    if (this.hasReviewIdentificationTarget) {
      const idType   = this._sel(el, "user[id_type]")
      const idNumber = this._val(el, "user[id_number]")
      const ninu     = this._val(el, "user[ninu]")
      const issuer   = this._sel(el, "user[document_issuer]")
      const issued   = this._date(el, "user[id_issued_on]")
      const expires  = this._date(el, "user[id_expires_on]")
      const birthDept    = this._sel(el, "user[birth_department_id]")
      const birthCommune = this._sel(el, "user[birth_commune_id]")
      const birthPlace   = [birthCommune, birthDept].filter(Boolean).join(", ")

      if (idType || idNumber) {
        const t = this.reviewIdentificationTarget
        let html = this._row(t, "id_type", "ID Type", idType) +
                   this._row(t, "id_number", "ID Number", idNumber)
        if (ninu) html += this._row(t, "ninu", "NINU", ninu)
        html += [
          this._row(t, "birth_place", "Place of Birth", birthPlace),
          this._row(t, "issued", "Issued", issued),
          this._row(t, "expires", "Expires", expires),
          this._row(t, "issuer", "Issuer", issuer)
        ].join("")
        this.reviewIdentificationTarget.innerHTML = html
      }
    }

    // ── Address (Haiti official format) ──
    if (this.hasReviewAddressTarget) {
      const section  = this._sel(el, "user[address_attributes][communal_section_id]")
      const street   = this._val(el, "user[address_attributes][street_address]")
      const commune  = this._sel(el, "user[address_attributes][commune_id]")
      const postal   = this._val(el, "user[address_attributes][postal_code]")
      const country  = this._sel(el, "user[address_attributes][country]") || "Haiti"

      if (section || commune || street) {
        const lines = []
        if (section) lines.push(this._esc(section))
        if (street) lines.push(this._esc(street))
        if (postal && commune) {
          lines.push(`${this._esc(postal.toUpperCase())}, ${this._esc(commune.toUpperCase())}`)
        }
        lines.push(this._esc(country.toUpperCase()))

        this.reviewAddressTarget.innerHTML = `<p class="mb-0" style="white-space: pre-line; line-height: 1.6;">${lines.join("\n")}</p>`
      }
    }
  }

  // ── Helpers ──
  _val(root, name) {
    const el = root.querySelector(`[name="${name}"]`)
    return el?.value?.trim() || ""
  }

  _sel(root, name) {
    const el = root.querySelector(`select[name="${name}"]`)
    if (!el || el.selectedIndex < 0) return ""
    const opt = el.options[el.selectedIndex]
    return (opt && opt.value) ? opt.text.trim() : ""
  }

  _date(root, name) {
    // Single date input
    const val = this._val(root, name)
    if (val && val.includes("-")) {
      const [y, m, d] = val.split("-")
      return this._formatDate(y, m, d)
    }
    // Rails date selects fallback: user[id_issued_on(1i)]
    const base = name.replace(/\]$/, "")
    const y = this._val(root, `${base}(1i)]`)
    const m = this._val(root, `${base}(2i)]`)
    const d = this._val(root, `${base}(3i)]`)
    if (!y || !m || !d) return ""
    return this._formatDate(y, m, d)
  }

  _formatDate(y, m, d) {
    const fallback = ["", "January", "February", "March", "April", "May", "June",
                      "July", "August", "September", "October", "November", "December"]
    const months = (this.hasMonthsValue && this.monthsValue.length === 13) ? this.monthsValue : fallback
    const month = months[parseInt(m, 10)] || m
    return this._l("date_format", "{month} {day}, {year}")
      .replace("{month}", month).replace("{day}", parseInt(d, 10)).replace("{year}", y)
  }

  // One "<strong>Label:</strong> value" review cell. `extra` is trusted HTML.
  _row(target, key, fallback, formValue, extra = "") {
    const label = this._l(key, fallback)
    return `<div class="col-sm-6"><strong>${this._esc(label)}:</strong> ${this._resolve(target, label, formValue)} ${extra}</div>`
  }

  _carrier(phone) {
    if (!phone) return ""
    const digits = phone.replace(/\D/g, "").replace(/^509/, "")
    const px = parseInt(digits.substring(0, 2), 10)
    const natcom = [28, 29, 35, 40, 41, 42, 43, 44, 45]
    const digicel = [31, 32, 33, 34, 36, 37, 38, 39, 46, 47, 48, 49]
    if (natcom.includes(px)) return '<span class="badge bg-light text-dark border ms-1" style="font-size: 0.7rem;">Natcom</span>'
    if (digicel.includes(px)) return '<span class="badge bg-light text-dark border ms-1" style="font-size: 0.7rem;">Digicel</span>'
    return ""
  }

  _esc(str) {
    if (!str) return ""
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }

  // For each <div class="col-sm-6"><strong>Label:</strong> Value</div> row
  // already in `target`, return the text after the matching <strong> label.
  // Used as a fallback when the form doesn't expose the value (locked fields).
  _existingValue(target, label) {
    if (!target) return ""
    const cells = target.querySelectorAll(".col-sm-6")
    for (const cell of cells) {
      const strong = cell.querySelector("strong")
      if (!strong) continue
      const cellLabel = strong.textContent.trim().replace(/:$/, "")
      if (cellLabel !== label) continue
      // Sum up text content after the <strong>, trimming the em-dash placeholder.
      let text = ""
      let node = strong.nextSibling
      while (node) {
        text += node.textContent || ""
        node = node.nextSibling
      }
      const trimmed = text.trim()
      return trimmed === "—" ? "" : trimmed
    }
    return ""
  }

  // Choose form value if present, else fall back to whatever was already
  // server-rendered for this label, else the em-dash placeholder.
  _resolve(target, label, formValue) {
    if (formValue) return this._esc(formValue)
    const existing = this._existingValue(target, label)
    return existing ? this._esc(existing) : "—"
  }
}
