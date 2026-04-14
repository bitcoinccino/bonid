// app/javascript/controllers/form_builder_controller.js
//
// Visual Form Builder — Google Forms-style field builder for partners.
// Supports multi-step wizard (Nouvo Paj), conditional logic, calculated
// fields, validation rules, and live preview. Partners never touch JSON.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "fieldList",     // container for field cards
    "preview",       // live preview container
    "structureJson", // hidden input that holds the final JSON
    "emptyState",    // "no fields yet" message
    "fieldCount",    // badge showing field count
    "stepTabs",      // step tab bar
    "categoryHint",      // category description card
    "pricingDetails",    // pricing amount section (shown/hidden)
    "priceInput",        // price input (HTG, not centimes)
    "priceCentsHidden",  // hidden field for actual centimes value
    "pricingConfig",     // pricing configuration container
    "pricingFeeList",    // mandatory fees list
    "pricingPreview",    // pricing total breakdown in preview
    "pricingType",       // hidden field for pricing_type (free/fixed)
    "departmentsData",   // JSON data for Haiti department cascade
    "powerFeatures",     // power features container
    "featureCapacity",   // transaction: capacity + event dates
    "featureCalendar",   // appointment: calendar hint
    "featureAnonymous"   // survey: anonymous hint
  ]

  // ─── Category descriptions (for dynamic hint card) ───
  static categoryDescriptions = {
    application: {
      icon: "ri-file-list-3-line",
      cls: "application",
      title: "Aplikasyon",
      desc: "Fòm konplè ak done detaye. Itilize bilding vizwèl la anba pou kreye etap ak chan."
    },
    appointment: {
      icon: "ri-calendar-check-line",
      cls: "appointment",
      title: "Randevou",
      desc: "Sitwayen an chwazi yon dat/lè ak rezon vizit. Pa bezwen fòm long."
    },
    transaction: {
      icon: "ri-exchange-dollar-line",
      cls: "transaction",
      title: "Tranzaksyon",
      desc: "Peman dirèk pou yon fakti, amann, oswa sèvis. Total ka varye selon chan nimewo/lajan."
    },
    survey: {
      icon: "ri-questionnaire-line",
      cls: "survey",
      title: "Sondaj & Fidbak",
      desc: "Koleksyon rapid opinyon oswa demann sipò. Jeneralman gratis — pa gen peman."
    }
  }

  connect() {
    // Use plain instance variables instead of Stimulus values for fields
    // (Stimulus values serialize to DOM attributes on every set, which is too heavy for per-keystroke updates)
    this._fields = []
    this._steps = []
    this._activeStep = ""
    this._priceMeta = {}
    this._departments = []

    // Load Haiti departments for address cascade
    if (this.hasDepartmentsDataTarget) {
      try { this._departments = JSON.parse(this.departmentsDataTarget.textContent) } catch { }
    }

    const existing = this.structureJsonTarget.value
    if (existing) {
      try {
        const parsed = JSON.parse(existing)
        this._fields = Array.isArray(parsed.fields) ? parsed.fields : []
        this._steps  = Array.isArray(parsed.steps)  ? parsed.steps  : []
        this._priceMeta = parsed.price_metadata || {}
      } catch {
        this._fields = []
        this._steps  = []
        this._priceMeta = {}
      }
    }

    // Set active step to first step if steps exist
    if (this._steps.length && !this._activeStep) {
      this._activeStep = this._steps[0].key
    }

    // Prevent Enter key from submitting the parent form in any builder input
    this.element.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && e.target.tagName === "INPUT" && e.target.type !== "submit") {
        e.preventDefault()
      }
    })

    // Combine split date+time inputs into hidden datetime fields (Randevou section)
    this.element.querySelectorAll("[data-datetime-combine]").forEach(input => {
      input.addEventListener("change", () => this._combineDatetime(input.dataset.datetimeCombine))
    })

    this.render()
    this.renderPricingConfig()

    // Show power features for current category on page load
    this._syncPowerFeatures()
  }

  _syncPowerFeatures() {
    const catSelect = this.element.querySelector("[name='partner_schema[service_category]']")
    if (!catSelect) return
    const cat = catSelect.value
    if (this.hasFeatureCapacityTarget) this.featureCapacityTarget.style.display = cat === "transaction" ? "block" : "none"
    if (this.hasFeatureCalendarTarget) this.featureCalendarTarget.style.display = cat === "appointment" ? "block" : "none"
    if (this.hasFeatureAnonymousTarget) this.featureAnonymousTarget.style.display = cat === "survey" ? "block" : "none"
  }

  // Combine split date + time → hidden datetime field (for starts_at / ends_at)
  _combineDatetime(fieldName) {
    const dateInput = this.element.querySelector(`[data-datetime-combine="${fieldName}"][type="date"]`)
    const timeInput = this.element.querySelector(`[data-datetime-combine="${fieldName}"][type="time"]`)
    const hidden = this.element.querySelector(`#${fieldName}_combined`)
    if (!dateInput || !timeInput || !hidden) return

    const d = dateInput.value
    const t = timeInput.value
    if (d && t) {
      hidden.value = `${d}T${t}:00`
    } else if (d) {
      hidden.value = `${d}T00:00:00`
    } else {
      hidden.value = ""
    }
  }

  // ─── Service Name Changed (live preview title) ─────────
  nameChanged() {
    this.renderPreview()
  }

  // ─── Auto-set pricing_type from price input ──────────
  priceChanged() {
    if (!this.hasPricingTypeTarget) return
    const val = parseFloat(this.priceInputTarget.value) || 0
    this.pricingTypeTarget.value = val > 0 ? "fixed" : "free"
    this.renderPricingPreview()
  }

  // ─── Currency Lock: single currency across all pricing ──
  // All fees + field add-ons use the same currency as Pri Debaz.
  // This is enforced by never storing currency per-fee — it's always
  // read from the base currency radio.
  getActiveCurrency() {
    const el = document.querySelector('input[name="partner_schema[currency]"]:checked')
    return el ? el.value : "HTG"
  }

  // ─── Pricing Configuration ──────────────────────────────

  renderPricingConfig() {
    if (!this.hasPricingConfigTarget) return
    const meta = this._priceMeta
    const fees = meta.mandatory_fees || []
    const currency = meta.currency || "HTG"

    let feesHtml = ""
    fees.forEach((fee, i) => {
      feesHtml += `
        <div class="fb-fee-row" data-fee-index="${i}">
          <input type="text" class="fb-input fb-fee-name" value="${this.escAttr(fee.name)}"
                 placeholder="Non frè a..." data-action="input->form-builder#updateFee"
                 data-fee-index="${i}" data-fee-prop="name">
          <input type="number" class="fb-input fb-fee-amount" value="${fee.amount || 0}"
                 min="0" step="0.01" placeholder="150 HTG"
                 data-action="input->form-builder#updateFee"
                 data-fee-index="${i}" data-fee-prop="amount">
          <select class="fb-input fb-fee-type" data-action="change->form-builder#updateFee"
                  data-fee-index="${i}" data-fee-prop="type">
            <option value="fixed" ${fee.type !== "percentage" ? "selected" : ""}>Fiks</option>
            <option value="percentage" ${fee.type === "percentage" ? "selected" : ""}>%</option>
          </select>
          <button type="button" class="fb-fee-remove" data-action="form-builder#removeFee"
                  data-fee-index="${i}" title="Retire">
            <i class="ri-close-line"></i>
          </button>
        </div>`
    })

    this.pricingConfigTarget.innerHTML = `
      ${feesHtml.length ? `
        <div class="fb-fee-list-header">
          <span class="fb-label">Frè & Taks Obligatwa</span>
        </div>
        <div data-form-builder-target="pricingFeeList">${feesHtml}</div>
      ` : ""}
      <button type="button" class="fb-add-fee-btn" data-action="form-builder#addFee">
        <i class="ri-add-line"></i> Ajoute Frè / Taks
      </button>
    `
    this.renderPricingPreview()
  }

  addFee() {
    if (!this._priceMeta.mandatory_fees) this._priceMeta.mandatory_fees = []
    this._priceMeta.mandatory_fees.push({ name: "", amount: 0, type: "fixed" })
    this.syncJson()
    this.renderPricingConfig()
  }

  removeFee(event) {
    const i = parseInt(event.currentTarget.dataset.feeIndex)
    if (!this._priceMeta.mandatory_fees) return
    this._priceMeta.mandatory_fees.splice(i, 1)
    this.syncJson()
    this.renderPricingConfig()
  }

  updateFee(event) {
    const i = parseInt(event.currentTarget.dataset.feeIndex)
    const prop = event.currentTarget.dataset.feeProp
    let val = event.currentTarget.value
    if (prop === "amount") val = parseFloat(val) || 0
    if (!this._priceMeta.mandatory_fees || !this._priceMeta.mandatory_fees[i]) return
    this._priceMeta.mandatory_fees[i][prop] = val
    this.syncJson()
    this.renderPricingPreview()
  }

  renderPricingPreview() {
    if (!this.hasPricingPreviewTarget) return
    const base = parseFloat(this.hasPriceInputTarget ? this.priceInputTarget.value : 0) || 0
    const currency = this._priceMeta.currency || "HTG"
    const fees = this._priceMeta.mandatory_fees || []

    if (base === 0 && fees.length === 0) {
      this.pricingPreviewTarget.innerHTML = `<div class="fb-price-summary fb-price-free"><i class="ri-gift-line"></i> Gratis</div>`
      return
    }

    let lines = []
    let total = base

    if (base > 0) {
      lines.push({ label: "Pri Debaz", amount: base })
    }

    fees.forEach(fee => {
      if (!fee.name && !fee.amount) return
      let amt = 0
      if (fee.type === "percentage") {
        amt = (base * (fee.amount || 0)) / 100
        lines.push({ label: `${fee.name || "Taks"} (${fee.amount}%)`, amount: amt })
      } else {
        amt = fee.amount || 0
        lines.push({ label: fee.name || "Frè", amount: amt })
      }
      total += amt
    })

    const sym = currency === "USD" ? "$" : ""
    const suffix = currency === "USD" ? "" : ` ${currency}`

    let html = `<div class="fb-price-summary">`
    lines.forEach(l => {
      html += `<div class="fb-price-line">
        <span>${this.escHtml(l.label)}</span>
        <span>${sym}${l.amount.toLocaleString("en", { minimumFractionDigits: 2 })}${suffix}</span>
      </div>`
    })
    if (lines.length > 1) {
      html += `<div class="fb-price-line fb-price-total">
        <span><strong>Total</strong></span>
        <span><strong>${sym}${total.toLocaleString("en", { minimumFractionDigits: 2 })}${suffix}</strong></span>
      </div>`
    }
    html += `</div>`
    this.pricingPreviewTarget.innerHTML = html
  }

  categoryChanged(event) {
    const cat = event.currentTarget.value

    if (this.hasCategoryHintTarget) {
      const info = this.constructor.categoryDescriptions[cat]
      if (!info) { this.categoryHintTarget.innerHTML = "" }
      else {
        this.categoryHintTarget.innerHTML = `
          <div class="fb-cat-card fb-cat-card--${info.cls}">
            <i class="${info.icon}"></i>
            <div>
              <strong>${info.title}</strong>
              <p>${info.desc}</p>
            </div>
          </div>`
      }
    }

    // Toggle power features per category
    if (this.hasFeatureCapacityTarget) this.featureCapacityTarget.style.display = cat === "transaction" ? "block" : "none"
    if (this.hasFeatureCalendarTarget) this.featureCalendarTarget.style.display = cat === "appointment" ? "block" : "none"
    if (this.hasFeatureAnonymousTarget) this.featureAnonymousTarget.style.display = cat === "survey" ? "block" : "none"

    // Auto-scaffold fields for simple categories (only if form is empty)
    if (this._fields.length === 0) {
      const scaffolds = {
        appointment: [
          { key: "appointment_date", label: "Dat Randevou", type: "date", required: true, step: "" },
          { key: "reason", label: "Rezon Vizit", type: "textarea", required: false, step: "" }
        ],
        transaction: [
          { key: "reference_number", label: "Nimewo Referans", type: "text", required: true, step: "", hint: "Nimewo fakti, amann, oswa kont" },
          { key: "amount_due", label: "Montan", type: "currency", required: true, step: "", currency: "HTG" }
        ],
        survey: [
          { key: "feedback", label: "Kòmantè Ou", type: "textarea", required: false, step: "", placeholder: "Pataje opinyon ou..." }
        ]
      }

      if (scaffolds[cat]) {
        this._fields = scaffolds[cat]
        this._steps = []
        this._activeStep = ""
        this.render()
      }
    }
  }

  // ═══════════════════════════════════════════════════════
  // MULTI-STEP / PAGE MANAGEMENT
  // ═══════════════════════════════════════════════════════

  addStep(event) {
    event.preventDefault()
    const stepNum = this._steps.length + 1
    const newStep = {
      key: `step_${Date.now()}`,
      name: `Etap ${stepNum}`
    }

    this._steps = [...this._steps, newStep]

    // If this is the first step, assign all existing fields to it
    if (this._steps.length === 1) {
      const fields = this._fields.map(f => ({ ...f, step: newStep.key }))
      this._fields = fields
    }

    this._activeStep = newStep.key
    this.render()
  }

  switchStep(event) {
    event.preventDefault()
    const stepKey = event.currentTarget.dataset.stepKey
    if (stepKey) {
      this._activeStep = stepKey
      this.render()
    }
  }

  renameStep(event) {
    const stepKey = event.currentTarget.dataset.stepKey
    const newName = event.currentTarget.value
    const steps = this._steps.map(s =>
      s.key === stepKey ? { ...s, name: newName } : s
    )
    this._steps = steps
    this.syncJson()
    this.renderPreview()
  }

  removeStep(event) {
    event.preventDefault()
    const stepKey = event.currentTarget.dataset.stepKey
    const steps = this._steps.filter(s => s.key !== stepKey)

    // Move orphaned fields to the first remaining step, or clear step
    const targetStep = steps.length ? steps[0].key : ""
    const fields = this._fields.map(f =>
      f.step === stepKey ? { ...f, step: targetStep } : f
    )

    this._steps = steps
    this._fields = fields
    this._activeStep = steps.length ? steps[0].key : ""
    this.render()
  }

  moveStepLeft(event) {
    event.preventDefault()
    const stepKey = event.currentTarget.dataset.stepKey
    const idx = this._steps.findIndex(s => s.key === stepKey)
    if (idx <= 0) return
    const steps = [...this._steps];
    [steps[idx - 1], steps[idx]] = [steps[idx], steps[idx - 1]]
    this._steps = steps
    this.render()
  }

  moveStepRight(event) {
    event.preventDefault()
    const stepKey = event.currentTarget.dataset.stepKey
    const idx = this._steps.findIndex(s => s.key === stepKey)
    if (idx < 0 || idx >= this._steps.length - 1) return
    const steps = [...this._steps];
    [steps[idx], steps[idx + 1]] = [steps[idx + 1], steps[idx]]
    this._steps = steps
    this.render()
  }

  // ═══════════════════════════════════════════════════════
  // FIELD MANAGEMENT
  // ═══════════════════════════════════════════════════════

  addField(event) {
    event.preventDefault()
    const type = event.currentTarget.dataset.fieldType || "text"
    const labels = {
      text: "Tèks", number: "Nimewo", currency: "Lajan",
      email: "Imèl", phone: "Telefòn", select: "Lis Dewoulan",
      radio: "Radyo", multi_checkbox: "Plizyè Chwa",
      checkbox: "Kaz Koche", file: "Fichye", date: "Dat", time: "Lè",
      textarea: "Tèks Long",
      datetime: "Dat & Lè",
      calculated: "Chan Kalkile",
      address: "Adrès",
      instructional_text: "Tèks Enstriksyon",
      section: "Nouvo Seksyon",
      bonid_signature: "Siyati BonID",
      seal_placeholder: "Anplasman Sèl",
      repeater: "Repetè"
    }

    const placeholders = {
      text: "Tape non ou isit...",
      email: "Ex: nom@gmail.com",
      phone: "Ex: 509 3456 7890",
      number: "Ex: 1",
      currency: "0.00",
      textarea: "Ekri repons ou isit...",
      date: "Ex: 01/01/2026",
      time: "Ex: 09:00",
      address: "Ri, Vil, Depatman..."
    }

    const field = {
      key: `field_${Date.now()}`,
      label: labels[type] || "New Field",
      type: type,
      required: false,
      placeholder: placeholders[type] || "",
      options: ["select", "radio", "multi_checkbox"].includes(type) ? "Opsyon 1,Opsyon 2,Opsyon 3" : "",
      step: this._activeStep || ""
    }

    if (type === "currency") {
      field.currency = "HTG"
    }

    if (type === "calculated") {
      field.calculation = ""
      field.currency = "HTG"
      field.required = false
    }

    // Address defaults — composite Haiti address block
    if (type === "address") {
      field.key = `address_${Date.now()}`
      field.label = "Adrès"
      field.required = false
    }

    // Instructional text defaults — inline help/context paragraph
    if (type === "instructional_text") {
      field.key = `instruction_${Date.now()}`
      field.label = ""
      field.description = "Antre enstriksyon oswa eksplikasyon isit..."
      field.style = "plain"
      field.required = false
    }

    // Section defaults — visual divider with title + optional description
    if (type === "section") {
      field.key = `section_${Date.now()}`
      field.label = "Nouvo Seksyon"
      field.description = ""
      field.required = false
    }

    // BonID Signature defaults
    if (type === "bonid_signature") {
      field.key = "bonid_signature"
      field.label = "Siyati BonID"
      field.required = true // consent is always required
    }

    // Seal placeholder defaults
    if (type === "seal_placeholder") {
      field.key = "official_seal"
      field.label = "Sèl Ofisyèl"
      field.required = false
    }

    // Repeater defaults — container for sub-field groups
    if (type === "repeater") {
      field.key = `repeater_${Date.now()}`
      field.label = "Gwoup Repetè"
      field.min_rows = 1
      field.max_rows = 10
      field.add_button_text = "+ Ajoute yon lòt"
      field.fields = []
      field.required = false
    }

    this._fields = [...this._fields, field]
    this.render()
  }

  loadTemplate(event) {
    event.preventDefault()
    const templateData = event.currentTarget.dataset.templateFields
    if (!templateData) return

    try {
      const fields = JSON.parse(templateData)
      // Assign all template fields to active step
      const step = this._activeStep || ""
      this._fields = fields.map(f => ({ ...f, step }))
      this.render()
    } catch (e) {
      console.warn("Failed to parse template:", e)
    }
  }

  updateField(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const prop = event.currentTarget.dataset.prop
    let value = event.currentTarget.type === "checkbox"
      ? event.currentTarget.checked
      : event.currentTarget.value

    const fields = [...this._fields]
    const realIndex = this.realIndex(index)
    if (realIndex < 0 || !fields[realIndex]) return

    fields[realIndex] = { ...fields[realIndex], [prop]: value }

    if (prop === "label") {
      fields[realIndex].key = value.toLowerCase()
        .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
        .replace(/[^a-z0-9]+/g, "_")
        .replace(/^_|_$/g, "")
        || `field_${realIndex}`
    }

    this._fields = fields
    this.syncJson()

    // Properties that change the field card layout need a full re-render
    if (["has_pricing", "currency", "filled_by"].includes(prop)) {
      this.render()
    } else {
      this.renderPreview()
    }
  }

  // ── Toggle "use my BonID address" for partner address ──
  togglePartnerBonidAddress(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const realIdx = this.realIndex(index)
    this._fields[realIdx] = {
      ...this._fields[realIdx],
      use_partner_bonid_address: event.currentTarget.checked
    }
    this.syncJson()
    this.render()
  }

  // ── Partner datetime combine handler ──
  partnerDatetimeChanged(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const realIdx = this.realIndex(index)
    const part = event.currentTarget.dataset.part
    const current = this._fields[realIdx].partner_value || ""
    const [datePart, timePart] = current.split("T")

    let newDate = part === "date" ? event.currentTarget.value : (datePart || "")
    let newTime = part === "time" ? event.currentTarget.value : (timePart || "")

    this._fields[realIdx] = {
      ...this._fields[realIdx],
      partner_value: newDate ? `${newDate}T${newTime || "00:00"}` : ""
    }
    this.syncJson()
  }

  // ── Partner address cascade handlers ──
  async partnerAddressDeptChanged(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const realIdx = this.realIndex(index)
    const deptId = event.currentTarget.value
    const slug = event.currentTarget.selectedOptions[0]?.dataset?.slug || deptId
    const deptName = event.currentTarget.selectedOptions[0]?.text || ""

    this._fields[realIdx] = {
      ...this._fields[realIdx],
      partner_department_id: deptId, partner_department: deptName,
      partner_arrondissement_id: "", partner_arrondissement: "",
      partner_commune_id: "", partner_commune: ""
    }
    this.syncJson()

    const arrSelect = document.getElementById(`fb_arr_${index}`)
    const comSelect = document.getElementById(`fb_com_${index}`)
    if (arrSelect) { arrSelect.innerHTML = '<option value="">— Awondisman —</option>' }
    if (comSelect) { comSelect.innerHTML = '<option value="">— Komin —</option>' }

    if (!deptId) return
    try {
      const resp = await fetch(`/departments/${slug}/arrondissements`)
      const data = await resp.json()
      data.forEach(a => arrSelect.add(new Option(a.name, a.id)))
    } catch (e) { console.warn("Arrondissement fetch failed:", e) }
  }

  async partnerAddressArrChanged(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const realIdx = this.realIndex(index)
    const arrId = event.currentTarget.value
    const arrName = event.currentTarget.selectedOptions[0]?.text || ""

    this._fields[realIdx] = {
      ...this._fields[realIdx],
      partner_arrondissement_id: arrId, partner_arrondissement: arrName,
      partner_commune_id: "", partner_commune: ""
    }
    this.syncJson()

    const comSelect = document.getElementById(`fb_com_${index}`)
    if (comSelect) { comSelect.innerHTML = '<option value="">— Komin —</option>' }

    if (!arrId) return
    try {
      const resp = await fetch(`/arrondissements/${arrId}/communes`)
      const data = await resp.json()
      data.forEach(c => comSelect.add(new Option(c.name, c.id)))
    } catch (e) { console.warn("Commune fetch failed:", e) }
  }

  partnerAddressComChanged(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const realIdx = this.realIndex(index)
    const comId = event.currentTarget.value
    const comName = event.currentTarget.selectedOptions[0]?.text || ""

    this._fields[realIdx] = {
      ...this._fields[realIdx],
      partner_commune_id: comId, partner_commune: comName
    }
    this.syncJson()
  }

  moveUp(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const visibleFields = this.visibleFields()
    if (index === 0) return

    const realA = this.realIndex(index - 1)
    const realB = this.realIndex(index)
    const fields = [...this._fields];
    [fields[realA], fields[realB]] = [fields[realB], fields[realA]]
    this._fields = fields
    this.render()
  }

  moveDown(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const visibleFields = this.visibleFields()
    if (index >= visibleFields.length - 1) return

    const realA = this.realIndex(index)
    const realB = this.realIndex(index + 1)
    const fields = [...this._fields];
    [fields[realA], fields[realB]] = [fields[realB], fields[realA]]
    this._fields = fields
    this.render()
  }

  removeField(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const realIdx = this.realIndex(index)
    const fields = [...this._fields]
    fields.splice(realIdx, 1)
    this._fields = fields
    this.render()
  }

  // ─── Collapse / Expand Field Card ─────────────────────
  toggleCollapse(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const realIdx = this.realIndex(index)
    if (realIdx < 0) return
    this._fields[realIdx]._collapsed = !this._fields[realIdx]._collapsed
    this.render()
  }

  // ─── Logic Rule Management ─────────────────────────────

  toggleLogic(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const panel = this.fieldListTarget.querySelector(`[data-logic-panel="${index}"]`)
    if (panel) {
      panel.style.display = panel.style.display === "none" ? "block" : "none"
    }
  }

  addVisibilityRule(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const realIdx = this.realIndex(index)
    const fields = [...this._fields]
    if (!fields[realIdx]) return

    const otherFields = fields.filter((_, i) => i !== realIdx)
    const defaultField = otherFields.length ? otherFields[0].key : ""
    const newRule = { field: defaultField, operator: "equals", value: "" }

    const existing = fields[realIdx].visible_if
    if (!existing) {
      // First rule — simple object
      fields[realIdx] = { ...fields[realIdx], visible_if: newRule }
    } else if (existing.all_of) {
      // Already has AND group — add to it
      fields[realIdx] = {
        ...fields[realIdx],
        visible_if: { ...existing, all_of: [...existing.all_of, newRule] }
      }
    } else if (existing.any_of) {
      // Already has OR group — add to it
      fields[realIdx] = {
        ...fields[realIdx],
        visible_if: { ...existing, any_of: [...existing.any_of, newRule] }
      }
    } else if (existing.field) {
      // Single rule exists — promote to all_of with both rules
      fields[realIdx] = {
        ...fields[realIdx],
        visible_if: { all_of: [existing, newRule] }
      }
    }

    this._fields = fields
    this.render()
  }

  removeVisibilityRule(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const ruleIndex = parseInt(event.currentTarget.dataset.ruleIndex || "0")
    const realIdx = this.realIndex(index)
    const fields = [...this._fields]
    if (!fields[realIdx]) return

    const existing = fields[realIdx].visible_if
    if (!existing) return

    // If it's a grouped condition (all_of / any_of)
    const groupKey = existing.all_of ? "all_of" : existing.any_of ? "any_of" : null
    if (groupKey) {
      const rules = [...existing[groupKey]]
      rules.splice(ruleIndex, 1)
      if (rules.length === 0) {
        const { visible_if, ...rest } = fields[realIdx]
        fields[realIdx] = rest
      } else if (rules.length === 1) {
        // Demote back to single rule
        fields[realIdx] = { ...fields[realIdx], visible_if: rules[0] }
      } else {
        fields[realIdx] = { ...fields[realIdx], visible_if: { [groupKey]: rules } }
      }
    } else {
      // Single rule — remove entirely
      const { visible_if, ...rest } = fields[realIdx]
      fields[realIdx] = rest
    }

    this._fields = fields
    this.render()
  }

  // Toggle between AND (all_of) and OR (any_of) logic
  toggleVisibilityLogicMode(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const realIdx = this.realIndex(index)
    const fields = [...this._fields]
    if (!fields[realIdx] || !fields[realIdx].visible_if) return

    const existing = fields[realIdx].visible_if
    if (existing.all_of) {
      fields[realIdx] = { ...fields[realIdx], visible_if: { any_of: existing.all_of } }
    } else if (existing.any_of) {
      fields[realIdx] = { ...fields[realIdx], visible_if: { all_of: existing.any_of } }
    }
    // Single rule — nothing to toggle

    this._fields = fields
    this.render()
  }

  updateVisibilityRule(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const ruleIndex = parseInt(event.currentTarget.dataset.ruleIndex || "0")
    const prop = event.currentTarget.dataset.ruleProp
    const value = event.currentTarget.value
    const realIdx = this.realIndex(index)

    const fields = [...this._fields]
    if (!fields[realIdx] || !fields[realIdx].visible_if) return

    const existing = fields[realIdx].visible_if
    const groupKey = existing.all_of ? "all_of" : existing.any_of ? "any_of" : null

    if (groupKey) {
      const rules = [...existing[groupKey]]
      if (rules[ruleIndex]) {
        rules[ruleIndex] = { ...rules[ruleIndex], [prop]: value }
        fields[realIdx] = { ...fields[realIdx], visible_if: { [groupKey]: rules } }
      }
    } else {
      // Single rule
      fields[realIdx] = {
        ...fields[realIdx],
        visible_if: { ...existing, [prop]: value }
      }
    }

    this._fields = fields
    this.syncJson()
  }

  updateCalculation(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const prop = event.currentTarget.dataset.calcProp
    const value = event.currentTarget.value
    const realIdx = this.realIndex(index)

    const fields = [...this._fields]
    if (!fields[realIdx]) return

    fields[realIdx] = { ...fields[realIdx], [prop]: value }
    this._fields = fields
    this.syncJson()
  }

  addValidationRule(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const realIdx = this.realIndex(index)
    const fields = [...this._fields]
    if (!fields[realIdx]) return

    const existing = fields[realIdx].validation_rules || []
    existing.push({ type: "min_length", value: "", message: "" })
    fields[realIdx] = { ...fields[realIdx], validation_rules: existing }
    this._fields = fields
    this.render()
  }

  removeValidationRule(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const ruleIndex = parseInt(event.currentTarget.dataset.ruleIndex)
    const realIdx = this.realIndex(index)
    const fields = [...this._fields]
    if (!fields[realIdx]) return

    const rules = [...(fields[realIdx].validation_rules || [])]
    rules.splice(ruleIndex, 1)
    fields[realIdx] = { ...fields[realIdx], validation_rules: rules.length ? rules : undefined }
    if (!rules.length) delete fields[realIdx].validation_rules
    this._fields = fields
    this.render()
  }

  updateValidationRule(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const ruleIndex = parseInt(event.currentTarget.dataset.ruleIndex)
    const prop = event.currentTarget.dataset.ruleProp
    const value = event.currentTarget.value
    const realIdx = this.realIndex(index)

    const fields = [...this._fields]
    if (!fields[realIdx]) return

    const rules = [...(fields[realIdx].validation_rules || [])]
    if (!rules[ruleIndex]) return
    rules[ruleIndex] = { ...rules[ruleIndex], [prop]: value }
    fields[realIdx] = { ...fields[realIdx], validation_rules: rules }
    this._fields = fields
    this.syncJson()
  }

  // ═══════════════════════════════════════════════════════
  // RENDERING
  // ═══════════════════════════════════════════════════════

  render() {
    this.renderStepTabs()
    this.renderFieldCards()
    this.renderPreview()
    this.syncJson()

    if (this.hasEmptyStateTarget) {
      const visible = this.visibleFields()
      this.emptyStateTarget.style.display = visible.length ? "none" : "block"
    }
    if (this.hasFieldCountTarget) {
      this.fieldCountTarget.textContent = this._fields.length
    }
  }

  // ─── Step Tabs ──────────────────────────────────────────
  renderStepTabs() {
    if (!this.hasStepTabsTarget) return
    const container = this.stepTabsTarget

    if (!this._steps.length) {
      container.innerHTML = ""
      container.style.display = "none"
      return
    }

    container.style.display = "flex"
    let html = ""

    this._steps.forEach((step, idx) => {
      const isActive = step.key === this._activeStep
      const fieldCount = this._fields.filter(f => f.step === step.key).length

      html += `
        <div class="fb-step-tab ${isActive ? 'fb-step-tab--active' : ''}" data-action="click->form-builder#switchStep" data-step-key="${step.key}">
          <div class="fb-step-tab-num">${idx + 1}</div>
          <input type="text" class="fb-step-tab-name" value="${this.escAttr(step.name)}"
                 data-action="input->form-builder#renameStep click->event#stopPropagation"
                 data-step-key="${step.key}"
                 placeholder="Non etap...">
          <span class="fb-step-tab-count">${fieldCount}</span>
          <div class="fb-step-tab-actions">
            ${idx > 0 ? `<button type="button" class="fb-step-tab-btn" data-action="click->form-builder#moveStepLeft" data-step-key="${step.key}" title="Deplase agoch"><i class="ri-arrow-left-s-line"></i></button>` : ""}
            ${idx < this._steps.length - 1 ? `<button type="button" class="fb-step-tab-btn" data-action="click->form-builder#moveStepRight" data-step-key="${step.key}" title="Deplase adwat"><i class="ri-arrow-right-s-line"></i></button>` : ""}
            <button type="button" class="fb-step-tab-btn fb-step-tab-btn--danger" data-action="click->form-builder#removeStep" data-step-key="${step.key}" title="Retire etap">
              <i class="ri-close-line"></i>
            </button>
          </div>
        </div>`
    })

    container.innerHTML = html
  }

  // ─── Field Cards ────────────────────────────────────────
  renderFieldCards() {
    const container = this.fieldListTarget
    container.innerHTML = ""

    const visible = this.visibleFields()

    visible.forEach((field, index) => {
      const card = document.createElement("div")
      card.className = "fb-field-card"

      const hasLogic = field.visible_if || field.calculation || (field.validation_rules && field.validation_rules.length)

      const isCollapsed = field._collapsed
      card.classList.toggle("fb-field-card--collapsed", !!isCollapsed)

      card.innerHTML = `
        <div class="fb-field-header">
          <div class="fb-field-drag">
            <i class="ri-draggable"></i>
          </div>
          <button type="button" class="fb-btn-collapse" data-action="form-builder#toggleCollapse" data-index="${index}" title="${isCollapsed ? 'Ouvri' : 'Fèmen'}">
            <i class="${isCollapsed ? 'ri-arrow-down-s-line' : 'ri-arrow-up-s-line'}"></i>
          </button>
          <span class="fb-field-type-badge">${this.typeIcon(field.type)} ${this.typeLabel(field.type)}</span>
          ${isCollapsed ? `<span class="fb-field-collapsed-label">${this.escHtml(field.label || "")}</span>` : ""}
          ${hasLogic ? '<span class="fb-logic-indicator" title="Lojik aktif"><i class="ri-git-branch-line"></i></span>' : ''}
          <div class="fb-field-actions">
            <button type="button" class="fb-btn-icon ${hasLogic ? 'fb-btn-logic-active' : ''}" data-action="form-builder#toggleLogic" data-index="${index}" title="Lojik">
              <i class="ri-git-branch-line"></i>
            </button>
            <button type="button" class="fb-btn-icon" data-action="form-builder#moveUp" data-index="${index}" title="Monte">
              <i class="ri-arrow-up-s-line"></i>
            </button>
            <button type="button" class="fb-btn-icon" data-action="form-builder#moveDown" data-index="${index}" title="Desann">
              <i class="ri-arrow-down-s-line"></i>
            </button>
            <button type="button" class="fb-btn-icon fb-btn-danger" data-action="form-builder#removeField" data-index="${index}" title="Retire">
              <i class="ri-delete-bin-line"></i>
            </button>
          </div>
        </div>
        ${field.type === "instructional_text" ? `
        <div class="fb-field-body fb-field-body--instructional">
          <div class="fb-field-row">
            <label class="fb-label">Tit <span class="fb-hint">(opsyonèl)</span></label>
            <input type="text" class="fb-input" value="${this.escAttr(field.label)}"
                   data-action="input->form-builder#updateField"
                   data-index="${index}" data-prop="label"
                   placeholder="Ex: Kòman pou w kalkile sa">
          </div>
          <div class="fb-field-row">
            <label class="fb-label">Tèks Enstriksyon</label>
            <textarea class="fb-input fb-input--hint" rows="3"
                   data-action="input->form-builder#updateField"
                   data-index="${index}" data-prop="description"
                   placeholder="Eksplikasyon, règ, oswa enstriksyon pou sitwayen an...">${this.escAttr(field.description || "")}</textarea>
            <span class="fb-hint">Itilize **gra** ak *italik* pou vize tèks enpòtan</span>
          </div>
          <div class="fb-field-row">
            <label class="fb-label">Estil</label>
            <select class="fb-input"
                    data-action="change->form-builder#updateField"
                    data-index="${index}" data-prop="style">
              <option value="plain" ${field.style === "plain" ? "selected" : ""}>Plenn — jis tèks</option>
              <option value="info" ${field.style === "info" ? "selected" : ""}>Enfòmasyon — bwat ble</option>
              <option value="warning" ${field.style === "warning" ? "selected" : ""}>Avètisman — bwat jòn</option>
              <option value="success" ${field.style === "success" ? "selected" : ""}>Siksè — bwat vèt</option>
            </select>
          </div>
        </div>
        ` : field.type === "address" ? `
        <div class="fb-field-body fb-field-body--address">
          <div class="fb-field-row">
            <label class="fb-label">Etikèt</label>
            <input type="text" class="fb-input" value="${this.escAttr(field.label)}"
                   data-action="input->form-builder#updateField"
                   data-index="${index}" data-prop="label"
                   placeholder="Ex: Adrès Lakay">
          </div>
          <div class="fb-address-preview-mini">
            <div class="fb-address-sub"><i class="ri-community-line"></i> Seksyon Kominal</div>
            <div class="fb-address-sub"><i class="ri-road-map-line"></i> Ri / Adrès</div>
            <div class="fb-address-sub"><i class="ri-building-line"></i> Lokalite</div>
            <div class="fb-address-sub"><i class="ri-map-2-line"></i> Depatman</div>
            <div class="fb-address-sub"><i class="ri-map-pin-2-line"></i> Awondisman</div>
            <div class="fb-address-sub"><i class="ri-map-pin-line"></i> Komin</div>
            <div class="fb-address-sub"><i class="ri-mail-send-line"></i> Kòd Postal</div>
          </div>
          <div class="fb-address-autofill-note">
            <i class="ri-shield-check-line"></i> Ap ranpli otomatikman ak pwofil BonID sitwayen an
          </div>
          <div class="fb-field-row">
            <label class="fb-label">Ranpli Pa <span class="fb-hint">(kilès ki ranpli chan sa a)</span></label>
            <div class="fb-radio-group">
              <label class="fb-radio-option">
                <input type="radio" name="filled_by_${index}" value="citizen"
                       ${!field.filled_by || field.filled_by === "citizen" ? "checked" : ""}
                       data-action="change->form-builder#updateField"
                       data-index="${index}" data-prop="filled_by">
                <span>Sitwayen</span>
              </label>
              <label class="fb-radio-option">
                <input type="radio" name="filled_by_${index}" value="partner"
                       ${field.filled_by === "partner" ? "checked" : ""}
                       data-action="change->form-builder#updateField"
                       data-index="${index}" data-prop="filled_by">
                <span>Patnè</span>
              </label>
            </div>
          </div>
          ${field.filled_by === "partner" ? `
          <div class="fb-partner-address-inputs" style="margin-top:0.5rem;padding:0.75rem;background:#f8f9fa;border-radius:0.5rem;border:1px solid #e5e7eb;">
            <label class="fb-label" style="margin-bottom:0.5rem;font-size:0.7rem;color:#6B7280;">Adrès Evènman <span class="fb-hint">(sitwayen ap wè sa)</span></label>
            <label style="display:flex;align-items:center;gap:0.4rem;margin-bottom:0.5rem;cursor:pointer;font-size:0.8rem;color:#00209F;">
              <input type="checkbox" ${field.use_partner_bonid_address ? "checked" : ""}
                     data-action="change->form-builder#togglePartnerBonidAddress"
                     data-index="${index}">
              <i class="ri-shield-check-line"></i> Itilize adrès BonID mwen
            </label>
            ${!field.use_partner_bonid_address ? `
            <input type="text" class="fb-input" value="${this.escAttr(field.partner_street || "")}"
                   data-action="input->form-builder#updateField"
                   data-index="${index}" data-prop="partner_street"
                   placeholder="Ri, nimewo kay..." style="margin-bottom:0.4rem;">
            <input type="text" class="fb-input" value="${this.escAttr(field.partner_locality || "")}"
                   data-action="input->form-builder#updateField"
                   data-index="${index}" data-prop="partner_locality"
                   placeholder="Katye, zòn..." style="margin-bottom:0.4rem;">
            <select class="fb-input" data-action="change->form-builder#partnerAddressDeptChanged"
                    data-index="${index}" style="margin-bottom:0.4rem;">
              <option value="">— Depatman —</option>
              ${this._departments.map(d => `<option value="${d.id}" data-slug="${d.slug}" ${field.partner_department_id == d.id ? "selected" : ""}>${d.name}</option>`).join("")}
            </select>
            <select class="fb-input" id="fb_arr_${index}" data-action="change->form-builder#partnerAddressArrChanged"
                    data-index="${index}" style="margin-bottom:0.4rem;">
              <option value="">— Awondisman —</option>
              ${field.partner_arrondissement_id ? `<option value="${field.partner_arrondissement_id}" selected>${field.partner_arrondissement || ""}</option>` : ""}
            </select>
            <select class="fb-input" id="fb_com_${index}" data-action="change->form-builder#partnerAddressComChanged"
                    data-index="${index}" style="margin-bottom:0.4rem;">
              <option value="">— Komin —</option>
              ${field.partner_commune_id ? `<option value="${field.partner_commune_id}" selected>${field.partner_commune || ""}</option>` : ""}
            </select>
            <input type="text" class="fb-input" value="${this.escAttr(field.partner_communal_section || "")}"
                   data-action="input->form-builder#updateField"
                   data-index="${index}" data-prop="partner_communal_section"
                   placeholder="Seksyon Kominal..." style="margin-bottom:0.4rem;">
            <input type="text" class="fb-input" value="${this.escAttr(field.partner_postal_code || "")}"
                   data-action="input->form-builder#updateField"
                   data-index="${index}" data-prop="partner_postal_code"
                   placeholder="Kòd Postal (ex: HT6110)">
            ` : `<div style="font-size:0.8rem;color:#059669;"><i class="ri-check-line"></i> Adrès BonID ou ap itilize otomatikman.</div>`}
          </div>
          ` : ""}
          <div class="fb-field-row fb-field-row--inline">
            <label class="fb-toggle">
              <input type="checkbox" ${field.required ? "checked" : ""}
                     data-action="change->form-builder#updateField"
                     data-index="${index}" data-prop="required">
              <span class="fb-toggle-slider"></span>
              <span class="fb-toggle-label">Obligatwa</span>
            </label>
          </div>
        </div>
        ` : field.type === "section" ? `
        <div class="fb-field-body fb-field-body--section">
          <div class="fb-field-row">
            <label class="fb-label">Tit Seksyon</label>
            <input type="text" class="fb-input fb-input--section-title" value="${this.escAttr(field.label)}"
                   data-action="input->form-builder#updateField"
                   data-index="${index}" data-prop="label"
                   placeholder="Ex: Enfòmasyon Pèsonèl">
          </div>
          <div class="fb-field-row">
            <label class="fb-label">Deskripsyon <span class="fb-hint">(opsyonèl)</span></label>
            <textarea class="fb-input fb-input--hint" rows="2"
                   data-action="input->form-builder#updateField"
                   data-index="${index}" data-prop="description"
                   placeholder="Eksplike sa seksyon sa a mande...">${this.escAttr(field.description || "")}</textarea>
          </div>
        </div>
        ` : field.type === "repeater" ? this.renderRepeaterFieldBody(field, index) : `
        <div class="fb-field-body">
          <div class="fb-field-row">
            <label class="fb-label">Etikèt</label>
            <input type="text" class="fb-input" value="${this.escAttr(field.label)}"
                   data-action="input->form-builder#updateField"
                   data-index="${index}" data-prop="label"
                   placeholder="Non chan an...">
          </div>
          ${!["bonid_signature", "seal_placeholder", "calculated", "checkbox"].includes(field.type) ? `
          <div class="fb-field-row">
            <label class="fb-label">Tèks Èd <span class="fb-hint">(opsyonèl — ede sitwayen an konprann)</span></label>
            <input type="text" class="fb-input fb-input--hint" value="${this.escAttr(field.hint || "")}"
                   data-action="input->form-builder#updateField"
                   data-index="${index}" data-prop="hint"
                   placeholder="Ex: Nou bezwen sa pou verifye idantite ou">
          </div>
          ${!["datetime", "date", "time", "file", "radio", "multi_checkbox"].includes(field.type) ? `
          <div class="fb-field-row">
            <label class="fb-label">${field.type === "select" ? "Tèks Envitasyon" : "Tèks Anba"} <span class="fb-hint">${field.type === "select" ? "(chwazi pa defo)" : "(placeholder — disparèt lè tape)"}</span></label>
            <input type="text" class="fb-input fb-input--hint" value="${this.escAttr(field.placeholder || "")}"
                   data-action="input->form-builder#updateField"
                   data-index="${index}" data-prop="placeholder"
                   placeholder="${field.type === "select" ? "Ex: Chwazi yon opsyon..." : field.type === "email" ? "Ex: nom@gmail.com" : field.type === "phone" ? "Ex: 509 3456 7890" : field.type === "number" || field.type === "currency" ? "Ex: 0.00" : field.type === "textarea" ? "Ex: Ekri repons ou isit..." : "Ex: Tape non ou isit..."}">
          </div>` : ""}` : ""}
          ${["select", "radio", "multi_checkbox"].includes(field.type) ?
            this.renderChoiceFieldBody(field, index) : ""}
          ${field.type === "currency" ? `
          <div class="fb-field-row">
            <label class="fb-label">Deviz</label>
            <div class="fb-radio-group">
              <label class="fb-radio-option">
                <input type="radio" name="currency_${index}" value="HTG"
                       ${field.currency === "HTG" || !field.currency ? "checked" : ""}
                       data-action="change->form-builder#updateField"
                       data-index="${index}" data-prop="currency">
                <span class="fb-radio-label">🇭🇹 HTG</span>
              </label>
              <label class="fb-radio-option">
                <input type="radio" name="currency_${index}" value="USD"
                       ${field.currency === "USD" ? "checked" : ""}
                       data-action="change->form-builder#updateField"
                       data-index="${index}" data-prop="currency">
                <span class="fb-radio-label">🇺🇸 USD</span>
              </label>
            </div>
          </div>` : ""}
          ${field.type === "datetime" ? this.renderDatetimeSettings(field, index) : ""}
          ${field.type === "number" ? this.renderQuantitySettings(field, index) : ""}
          ${field.type === "calculated" ? this.renderCalculatedFieldBody(field, index) : ""}
          <div class="fb-field-row">
            <label class="fb-label">Ranpli Pa <span class="fb-hint">(kilès ki ranpli chan sa a)</span></label>
            <div class="fb-radio-group">
              <label class="fb-radio-option">
                <input type="radio" name="filled_by_${index}" value="citizen"
                       ${!field.filled_by || field.filled_by === "citizen" ? "checked" : ""}
                       data-action="change->form-builder#updateField"
                       data-index="${index}" data-prop="filled_by">
                <span>Sitwayen</span>
              </label>
              <label class="fb-radio-option">
                <input type="radio" name="filled_by_${index}" value="partner"
                       ${field.filled_by === "partner" ? "checked" : ""}
                       data-action="change->form-builder#updateField"
                       data-index="${index}" data-prop="filled_by">
                <span>Patnè</span>
              </label>
            </div>
          </div>
          ${field.filled_by === "partner" ? `
          <div class="fb-field-row" style="padding:0.5rem;background:#f8f9fa;border-radius:0.375rem;border:1px solid #e5e7eb;">
            <label class="fb-label" style="font-size:0.7rem;color:#6B7280;">Valè Patnè <span class="fb-hint">(sitwayen ap wè sa)</span></label>
            ${field.type === "datetime" ? `
              <div style="display:flex;gap:0.4rem;">
                <input type="date" class="fb-input" value="${this.escAttr((field.partner_value || "").split("T")[0] || "")}"
                       data-action="change->form-builder#partnerDatetimeChanged"
                       data-index="${index}" data-part="date" style="flex:1;">
                <input type="time" class="fb-input" value="${this.escAttr((field.partner_value || "").split("T")[1] || "")}"
                       data-action="change->form-builder#partnerDatetimeChanged"
                       data-index="${index}" data-part="time" style="flex:1;">
              </div>
            ` : field.type === "textarea" ? `
              <textarea class="fb-input" rows="2"
                     data-action="input->form-builder#updateField"
                     data-index="${index}" data-prop="partner_value"
                     placeholder="Tape valè a...">${this.escAttr(field.partner_value || "")}</textarea>
            ` : `
              <input type="${field.type === "email" ? "email" : field.type === "phone" ? "tel" : field.type === "number" || field.type === "currency" ? "number" : "text"}" class="fb-input" value="${this.escAttr(field.partner_value || "")}"
                     data-action="input->form-builder#updateField"
                     data-index="${index}" data-prop="partner_value"
                     placeholder="Tape valè a...">
            `}
          </div>
          ` : ""}
          <div class="fb-field-row fb-field-row--inline">
            <label class="fb-toggle">
              <input type="checkbox" ${field.required ? "checked" : ""}
                     data-action="change->form-builder#updateField"
                     data-index="${index}" data-prop="required">
              <span class="fb-toggle-slider"></span>
              <span class="fb-toggle-label">Obligatwa</span>
            </label>
          </div>
        </div>
        `}

        ${/* ── Logic Panel ── */""}
        <div class="fb-logic-panel" data-logic-panel="${index}" style="display: none;">
          <div class="fb-logic-header">
            <i class="ri-git-branch-line"></i> Lojik & Règ
          </div>
          <div class="fb-logic-section">
            <div class="fb-logic-section-title">
              <i class="ri-eye-line"></i> Vizibilite Kondisyonèl
              <span class="fb-hint">Montre/kache chan sa a selon yon lòt chan</span>
            </div>
            ${field.visible_if ? this.renderVisibilityRule(field, index) : ""}
            <button type="button" class="fb-logic-add-btn" data-action="form-builder#addVisibilityRule" data-index="${index}">
              <i class="ri-add-line"></i> ${field.visible_if ? "Ajoute Lòt Kondisyon" : "Ajoute Kondisyon"}
            </button>
          </div>
          <div class="fb-logic-section">
            <div class="fb-logic-section-title">
              <i class="ri-shield-check-line"></i> Validasyon Avanse
              <span class="fb-hint">Règ pou anpeche soumisyon si kondisyon pa ranpli</span>
            </div>
            ${this.renderValidationRules(field, index)}
            <button type="button" class="fb-logic-add-btn" data-action="form-builder#addValidationRule" data-index="${index}">
              <i class="ri-add-line"></i> Ajoute Règ
            </button>
          </div>
        </div>
      `
      container.appendChild(card)
    })
  }

  // ─── Visibility Rule UI ──────────────────────────────
  renderVisibilityRule(field, index) {
    const visIf = field.visible_if
    const otherFields = this._fields
      .map((f, i) => ({ key: f.key, label: f.label, index: i }))
      .filter(f => f.key !== field.key)

    // Normalize rules into an array
    let rules = []
    let logicMode = "all_of" // default AND
    if (visIf.all_of) {
      rules = visIf.all_of
      logicMode = "all_of"
    } else if (visIf.any_of) {
      rules = visIf.any_of
      logicMode = "any_of"
    } else if (visIf.field) {
      rules = [visIf] // single rule
    }

    const operators = [
      { value: "equals", label: "egal a" },
      { value: "not_equals", label: "pa egal a" },
      { value: "greater_than", label: "pi gran pase" },
      { value: "less_than", label: "pi piti pase" },
      { value: "contains", label: "kontni" },
      { value: "is_empty", label: "vid" },
      { value: "is_not_empty", label: "pa vid" }
    ]

    let html = ""

    // AND/OR toggle (only show if multiple rules)
    if (rules.length > 1) {
      const isAnd = logicMode === "all_of"
      html += `
        <div class="fb-logic-mode">
          <span class="fb-logic-mode-label">Lojik:</span>
          <button type="button" class="fb-logic-mode-btn ${isAnd ? 'fb-logic-mode-btn--active' : ''}"
                  data-action="form-builder#toggleVisibilityLogicMode" data-index="${index}">
            ${isAnd ? '<i class="ri-link"></i> TOUT (AND)' : '<i class="ri-link-unlink"></i> NENPÒT (OR)'}
          </button>
          <span class="fb-hint">${isAnd ? "Tout kondisyon dwe vre" : "Nenpòt kondisyon ka vre"}</span>
        </div>`
    }

    rules.forEach((rule, ruleIndex) => {
      const fieldOptions = otherFields.map(f =>
        `<option value="${this.escAttr(f.key)}" ${rule.field === f.key ? "selected" : ""}>${this.escHtml(f.label)}</option>`
      ).join("")

      const operatorOptions = operators.map(op =>
        `<option value="${op.value}" ${rule.operator === op.value ? "selected" : ""}>${op.label}</option>`
      ).join("")

      const needsValue = !["is_empty", "is_not_empty"].includes(rule.operator)
      const connector = ruleIndex > 0 ? `<span class="fb-logic-connector">${logicMode === "all_of" ? "AK" : "OSWA"}</span>` : ""

      html += `
        ${connector}
        <div class="fb-logic-rule">
          <div class="fb-logic-rule-row">
            <span class="fb-logic-label">${ruleIndex === 0 ? "Montre si" : ""}</span>
            <select class="fb-input fb-logic-input" data-action="change->form-builder#updateVisibilityRule"
                    data-index="${index}" data-rule-index="${ruleIndex}" data-rule-prop="field">
              <option value="">-- Chwazi chan --</option>
              ${fieldOptions}
            </select>
            <select class="fb-input fb-logic-input" data-action="change->form-builder#updateVisibilityRule"
                    data-index="${index}" data-rule-index="${ruleIndex}" data-rule-prop="operator">
              ${operatorOptions}
            </select>
            ${needsValue ? `
            <input type="text" class="fb-input fb-logic-input" value="${this.escAttr(rule.value || "")}"
                   data-action="input->form-builder#updateVisibilityRule"
                   data-index="${index}" data-rule-index="${ruleIndex}" data-rule-prop="value"
                   placeholder="Valè...">` : ""}
          </div>
          <button type="button" class="fb-logic-remove" data-action="form-builder#removeVisibilityRule"
                  data-index="${index}" data-rule-index="${ruleIndex}" title="Retire kondisyon">
            <i class="ri-close-line"></i>
          </button>
        </div>`
    })

    return html
  }

  // ─── Validation Rules UI ─────────────────────────────
  renderValidationRules(field, index) {
    const rules = field.validation_rules || []
    if (!rules.length) return ""

    const validationTypes = [
      { value: "min_length", label: "Longè minimòm" },
      { value: "max_length", label: "Longè maksimòm" },
      { value: "min_value", label: "Valè minimòm" },
      { value: "max_value", label: "Valè maksimòm" },
      { value: "pattern", label: "Modèl (regex)" },
      { value: "requires_one_of", label: "Bezwen youn nan" }
    ]

    return rules.map((rule, ruleIndex) => {
      const typeOptions = validationTypes.map(vt =>
        `<option value="${vt.value}" ${rule.type === vt.value ? "selected" : ""}>${vt.label}</option>`
      ).join("")

      return `
        <div class="fb-logic-rule">
          <div class="fb-logic-rule-row">
            <select class="fb-input fb-logic-input" data-action="change->form-builder#updateValidationRule"
                    data-index="${index}" data-rule-index="${ruleIndex}" data-rule-prop="type">
              ${typeOptions}
            </select>
            <input type="text" class="fb-input fb-logic-input" value="${this.escAttr(rule.value || "")}"
                   data-action="input->form-builder#updateValidationRule"
                   data-index="${index}" data-rule-index="${ruleIndex}" data-rule-prop="value"
                   placeholder="${rule.type === "requires_one_of" ? "chan_1, chan_2" : "Valè..."}">
            <input type="text" class="fb-input fb-logic-input" value="${this.escAttr(rule.message || "")}"
                   data-action="input->form-builder#updateValidationRule"
                   data-index="${index}" data-rule-index="${ruleIndex}" data-rule-prop="message"
                   placeholder="Mesaj erè (opsyonèl)">
          </div>
          <button type="button" class="fb-logic-remove" data-action="form-builder#removeValidationRule"
                  data-index="${index}" data-rule-index="${ruleIndex}" title="Retire règ">
            <i class="ri-close-line"></i>
          </button>
        </div>`
    }).join("")
  }

  // ─── Live Preview (Multi-Step Wizard) ────────────────────
  renderPreview() {
    if (!this.hasPreviewTarget) return
    const container = this.previewTarget

    if (!this._fields.length) {
      container.innerHTML = `
        <div class="fb-preview-empty">
          <i class="ri-eye-off-line"></i>
          <p>Ajoute chan pou wè apèsi fòm nan.</p>
        </div>`
      return
    }

    const hasSteps = this._steps.length > 0
    let html = ""

    // ── Service name + description header ──
    const nameEl = this.element.querySelector('input[name="partner_schema[name]"]')
    const descEl = this.element.querySelector('input[name="partner_schema[description]"]')
    const svcName = nameEl ? nameEl.value.trim() : ""
    const svcDesc = descEl ? descEl.value.trim() : ""
    if (svcName) {
      html += `<div class="fb-preview-header">
        <h3 class="fb-preview-svc-name">${this.escHtml(svcName)}</h3>
        ${svcDesc ? `<p class="fb-preview-svc-desc">${this.escHtml(svcDesc)}</p>` : ""}
      </div>`
    }

    if (hasSteps) {
      // ── Multi-step preview with progress bar ──
      html += `<div class="fb-preview-stepper">`

      // Progress bar
      html += `<div class="fb-preview-progress">`
      this._steps.forEach((step, idx) => {
        const stepFields = this._fields.filter(f => f.step === step.key)
        html += `
          <div class="fb-preview-progress-step ${idx === 0 ? 'fb-preview-progress-step--active' : ''}">
            <div class="fb-preview-progress-dot">${idx + 1}</div>
            <span class="fb-preview-progress-label">${this.escHtml(step.name)}</span>
          </div>`
        if (idx < this._steps.length - 1) {
          html += `<div class="fb-preview-progress-line"></div>`
        }
      })
      html += `</div>`

      // Step panels (show all stacked for preview)
      this._steps.forEach((step, idx) => {
        const stepFields = this._fields.filter(f => f.step === step.key)
        html += `
          <div class="fb-preview-step">
            <div class="fb-preview-step-header">
              <span class="fb-preview-step-num">Etap ${idx + 1} sou ${this._steps.length}</span>
              <span class="fb-preview-step-name">${this.escHtml(step.name)}</span>
            </div>`

        stepFields.filter(f => f.filled_by !== "partner").forEach(field => {
          html += this.renderPreviewField(field)
        })

        // Step navigation buttons
        html += `<div class="fb-preview-step-nav">`
        if (idx > 0) {
          html += `<button type="button" class="fb-preview-nav-btn fb-preview-nav-btn--back" disabled>
            <i class="ri-arrow-left-s-line"></i> Retounen
          </button>`
        }
        if (idx < this._steps.length - 1) {
          html += `<button type="button" class="fb-preview-nav-btn fb-preview-nav-btn--next" disabled>
            Kontinye <i class="ri-arrow-right-s-line"></i>
          </button>`
        } else {
          html += `<button type="button" class="fb-preview-nav-btn fb-preview-nav-btn--submit" disabled>
            <i class="ri-check-line"></i> Soumèt
          </button>`
        }
        html += `</div></div>`
      })

      html += `</div>`
    } else {
      // ── Single-page preview ──
      this._fields.filter(f => f.filled_by !== "partner").forEach(field => {
        html += this.renderPreviewField(field)
      })
    }

    // ── Pricing summary at bottom of preview ──
    html += this.renderPreviewPricing()

    container.innerHTML = html
  }

  renderPreviewPricing() {
    const base = parseFloat(this.hasPriceInputTarget ? this.priceInputTarget.value : 0) || 0
    const fees = (this._priceMeta && this._priceMeta.mandatory_fees) || []

    // Collect optional add-on fields with priced options
    const addOnFields = this._fields.filter(f =>
      f.has_pricing && ["select", "radio", "multi_checkbox"].includes(f.type)
    )

    // Collect repeater fields with price-per-row
    const pricedRepeaters = this._fields.filter(f =>
      f.type === "repeater" && f.has_pricing && parseFloat(f.price_per_row) > 0
    )

    if (base === 0 && fees.length === 0 && addOnFields.length === 0 && pricedRepeaters.length === 0) return ""

    const currency = this.getActiveCurrency()
    const sym = currency === "USD" ? "$" : ""
    const sfx = currency === "USD" ? "" : ` ${currency}`
    const fmt = (n) => `${sym}${n.toLocaleString("en", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}${sfx}`

    let html = `<div class="fb-preview-pricing">`
    html += `<div class="fb-preview-pricing-title"><i class="ri-price-tag-3-line"></i> Estimasyon Pri</div>`

    // Base + mandatory fees = mandatory total
    let mandatoryTotal = base
    if (base > 0) {
      html += `<div class="fb-price-line"><span>Pri Debaz</span><span>${fmt(base)}</span></div>`
    }

    fees.forEach(fee => {
      if (!fee.name && !fee.amount) return
      let amt = 0
      const kind = fee.type || fee.kind
      if (kind === "percentage" || kind === "percent") {
        amt = (base * (fee.amount || fee.value || 0)) / 100
        html += `<div class="fb-price-line"><span>${this.escHtml(fee.name || "Taks")} (${fee.amount || fee.value}%)</span><span>${fmt(amt)}</span></div>`
      } else {
        amt = fee.amount || fee.value || 0
        html += `<div class="fb-price-line"><span>${this.escHtml(fee.name || "Frè")}</span><span>${fmt(amt)}</span></div>`
      }
      mandatoryTotal += amt
    })

    // Calculate min/max from optional field add-ons
    let minAddons = 0
    let maxAddons = 0

    addOnFields.forEach(field => {
      const opts = this.parseOptions(field.options)
      const prices = opts.map(o => o.extra_price || 0).filter(p => p !== 0)
      if (!prices.length) return

      if (field.type === "multi_checkbox") {
        // Multi: min = sum of negatives (discounts), max = sum of positives
        minAddons += prices.filter(p => p < 0).reduce((s, p) => s + p, 0)
        maxAddons += prices.filter(p => p > 0).reduce((s, p) => s + p, 0)
      } else {
        // Single select/radio: min = cheapest, max = most expensive
        minAddons += Math.min(...prices, 0)
        maxAddons += Math.max(...prices, 0)
      }
    })

    if (addOnFields.length > 0) {
      html += `<div class="fb-price-line fb-price-line--addons"><span><i class="ri-add-circle-line"></i> Opsyon sitwayen chwazi</span><span>${minAddons !== maxAddons ? `${fmt(minAddons)} — ${fmt(maxAddons)}` : fmt(maxAddons)}</span></div>`
    }

    // Repeater price-per-row (show min..max range based on min_rows..max_rows)
    let minRepeater = 0
    let maxRepeater = 0
    pricedRepeaters.forEach(rep => {
      const perRow = parseFloat(rep.price_per_row) || 0
      const minR = parseInt(rep.min_rows) || 1
      const maxR = parseInt(rep.max_rows) || 10
      minRepeater += perRow * minR
      maxRepeater += perRow * maxR
      html += `<div class="fb-price-line fb-price-line--repeater"><span><i class="ri-repeat-line"></i> ${this.escHtml(rep.label)} (${fmt(perRow)}/ranje)</span><span>${minR}–${maxR} ranje</span></div>`
    })
    minAddons += minRepeater
    maxAddons += maxRepeater

    // Show min/max totals
    const minTotal = mandatoryTotal + minAddons
    const maxTotal = mandatoryTotal + maxAddons
    const hasRange = maxTotal !== minTotal

    if (fees.length > 0 || addOnFields.length > 0) {
      if (hasRange) {
        html += `<div class="fb-price-line fb-price-total">
          <span><strong>Minimòm</strong></span>
          <span><strong>${fmt(minTotal)}</strong></span>
        </div>`
        html += `<div class="fb-price-line fb-price-max">
          <span><strong>Maksimòm Posib</strong></span>
          <span><strong>${fmt(maxTotal)}</strong></span>
        </div>`
      } else {
        html += `<div class="fb-price-line fb-price-total">
          <span><strong>Total</strong></span>
          <span><strong>${fmt(minTotal)}</strong></span>
        </div>`
      }
    }

    html += `</div>`
    return html
  }

  /**
   * Minority Rule: mark whichever type (required/optional) is less common.
   * Returns the indicator HTML for a field's label.
   */
  labelIndicator(field) {
    if (["bonid_signature", "seal_placeholder", "calculated", "section", "instructional_text", "address"].includes(field.type)) return ""

    // Count required vs optional across all form fields (excluding non-input types)
    const formFields = this._fields.filter(f => !["bonid_signature", "seal_placeholder", "calculated", "section", "instructional_text", "address"].includes(f.type))
    const requiredCount = formFields.filter(f => f.required).length
    const optionalCount = formFields.length - requiredCount
    const markOptional = requiredCount >= optionalCount

    if (markOptional && !field.required) {
      return '<span class="fb-preview-indicator fb-preview-indicator--optional">(opsyonèl)</span>'
    } else if (!markOptional && field.required) {
      return '<span class="fb-preview-indicator fb-preview-indicator--required">(obligatwa)</span>'
    }
    return ""
  }

  // ── Choice field body (select/radio/multi_checkbox) ──
  renderChoiceFieldBody(field, index) {
    const defaults = Array.isArray(field.default_values) ? field.default_values : (field.default_value ? [field.default_value] : [])
    const parsedOpts = this.parseOptions(field.options)

    const hasPricing = !!field.has_pricing
    let chipsHtml = ""
    parsedOpts.forEach((opt, oi) => {
      const isDefault = defaults.includes(opt.value)
      const extraPrice = opt.extra_price || 0
      const priceClass = extraPrice > 0 ? 'fb-chip--priced' : (extraPrice < 0 ? 'fb-chip--discount' : '')
      chipsHtml += `
        <div class="fb-chip ${isDefault ? 'fb-chip--default' : ''} ${priceClass}">
          <button type="button" class="fb-chip-star" data-action="form-builder#toggleDefault" data-index="${index}" data-option-index="${oi}" title="${isDefault ? 'Retire pa defo' : 'Make pa defo'}">
            <i class="${isDefault ? 'ri-star-fill' : 'ri-star-line'}"></i>
          </button>
          <span class="fb-chip-label">${this.escHtml(opt.label)}</span>
          ${opt.value !== opt.label ? `<span class="fb-chip-value">${this.escHtml(opt.value)}</span>` : ""}
          ${hasPricing ? `<input type="number" class="fb-chip-price" value="${extraPrice || ''}" step="0.01" placeholder="0" data-action="input->form-builder#updateOptionPrice" data-index="${index}" data-option-index="${oi}" title="Pri adisyonèl">` : ""}
          <button type="button" class="fb-chip-remove" data-action="form-builder#removeOption" data-index="${index}" data-option-index="${oi}" title="Retire">&times;</button>
        </div>`
    })

    let html = `
      <div class="fb-field-row">
        <div class="fb-option-header">
          <label class="fb-label">Opsyon yo</label>
          <div class="fb-option-actions">
            ${parsedOpts.length > 2 ? `
              <button type="button" class="fb-option-action-btn" data-action="form-builder#clearAllOptions" data-index="${index}" title="Retire tout">
                <i class="ri-delete-bin-line"></i> Retire Tout
              </button>` : ""}
          </div>
        </div>
        <div class="fb-option-chips" data-index="${index}">${chipsHtml}</div>
        <div class="fb-option-add-row">
          <input type="text" class="fb-input fb-option-input" data-index="${index}"
                 placeholder="Tape opsyon epi peze Enter"
                 data-action="keydown->form-builder#optionKeydown">
          <button type="button" class="fb-option-add-btn" data-action="form-builder#addOptionFromInput" data-index="${index}" title="Ajoute">
            <i class="ri-add-line"></i>
          </button>
        </div>
        <div class="fb-option-error" data-option-error="${index}" style="display:none;"></div>
        <span class="fb-hint">Tape chak chwa epi peze Enter pou ajoute li</span>
      </div>
      <div class="fb-field-row">
        <label class="fb-label">Mòd Seleksyon</label>
        <div class="fb-mode-toggle">
          <button type="button" class="fb-mode-btn ${field.type === 'select' ? 'fb-mode-btn--active' : ''}"
                  data-action="form-builder#switchChoiceMode" data-index="${index}" data-mode="select" title="Lis dewoulan">
            <i class="ri-list-check"></i> Dewoulan
          </button>
          <button type="button" class="fb-mode-btn ${field.type === 'radio' ? 'fb-mode-btn--active' : ''}"
                  data-action="form-builder#switchChoiceMode" data-index="${index}" data-mode="radio" title="Yon sèl chwa">
            <i class="ri-radio-button-line"></i> Radyo
          </button>
          <button type="button" class="fb-mode-btn ${field.type === 'multi_checkbox' ? 'fb-mode-btn--active' : ''}"
                  data-action="form-builder#switchChoiceMode" data-index="${index}" data-mode="multi_checkbox" title="Plizyè chwa">
            <i class="ri-checkbox-multiple-line"></i> Plizyè
          </button>
        </div>
      </div>`

    // Pricing impact toggle — show price inputs on each option
    html += `
    <div class="fb-field-row fb-field-row--inline" style="gap: 1rem;">
      <label class="fb-toggle">
        <input type="checkbox" ${field.has_pricing ? "checked" : ""}
               data-action="change->form-builder#updateField"
               data-index="${index}" data-prop="has_pricing">
        <span class="fb-toggle-slider"></span>
        <span class="fb-toggle-label"><i class="ri-price-tag-3-line"></i> Enpak Pri</span>
      </label>
    </div>`

    if (field.type === "select") {
      html += `
      <div class="fb-field-row fb-field-row--inline" style="gap: 1rem;">
        <label class="fb-toggle">
          <input type="checkbox" ${field.sort_alpha ? "checked" : ""}
                 data-action="change->form-builder#updateField"
                 data-index="${index}" data-prop="sort_alpha">
          <span class="fb-toggle-slider"></span>
          <span class="fb-toggle-label">Triye Alfabetikman</span>
        </label>
        <label class="fb-toggle">
          <input type="checkbox" ${field.searchable ? "checked" : ""}
                 data-action="change->form-builder#updateField"
                 data-index="${index}" data-prop="searchable">
          <span class="fb-toggle-slider"></span>
          <span class="fb-toggle-label">Pèmèt Rechèch</span>
        </label>
      </div>`
    }

    return html
  }

  // ─── Quantity Settings (for number fields) ──────────────────────
  // ─── Datetime Settings — "must be after" link ─────────
  renderDatetimeSettings(field, index) {
    // Collect other datetime fields the partner could link to
    const otherDatetimes = this._fields
      .filter(f => f.type === "datetime" && f.key !== field.key)
      .map(f => ({ value: f.key, label: f.label || f.key }))

    if (otherDatetimes.length === 0) return ""

    return `
      <div class="fb-field-row">
        <label class="fb-label">Dwe apre <span class="fb-hint">(opsyonèl — dat/lè sa a dwe vin apre yon lòt)</span></label>
        <select class="fb-input"
                data-action="change->form-builder#updateField"
                data-index="${index}" data-prop="after_field">
          <option value="">— Pa gen kontrènt —</option>
          ${otherDatetimes.map(dt => `<option value="${dt.value}" ${field.after_field === dt.value ? "selected" : ""}>${this.escHtml(dt.label)}</option>`).join("")}
        </select>
      </div>`
  }

  renderQuantitySettings(field, index) {
    const isQty = !!field.is_quantity

    // Build list of linkable price targets: currency fields + base price
    const priceTargets = []
    priceTargets.push({ value: "__base_price__", label: "Pri Debaz Sèvis" })
    this._fields.forEach(f => {
      if (f.type === "currency" && f.key !== field.key) {
        priceTargets.push({ value: f.key, label: f.label || f.key })
      }
      // Include radio/select/multi_checkbox fields with pricing enabled
      if (["select", "radio", "multi_checkbox"].includes(f.type) && f.has_pricing && f.key !== field.key) {
        priceTargets.push({ value: f.key, label: (f.label || f.key) + " (opsyon pri)" })
      }
    })

    let html = `
      <div class="fb-field-row fb-field-row--inline">
        <label class="fb-toggle">
          <input type="checkbox" ${isQty ? "checked" : ""}
                 data-action="change->form-builder#toggleQuantity"
                 data-index="${index}">
          <span class="fb-toggle-slider"></span>
          <span class="fb-toggle-label">Sèvi kòm Kantite</span>
        </label>
      </div>`

    if (isQty) {
      html += `
      <div class="fb-qty-settings">
        <div class="fb-field-row">
          <label class="fb-label">Miltipliye ak</label>
          <select class="fb-input"
                  data-action="change->form-builder#updateField"
                  data-index="${index}" data-prop="linked_to_field">
            ${priceTargets.map(t => `<option value="${t.value}" ${field.linked_to_field === t.value ? "selected" : ""}>${t.label}</option>`).join("")}
          </select>
        </div>
        <div class="fb-qty-row">
          <div class="fb-qty-col">
            <label class="fb-label">Min</label>
            <input type="number" class="fb-input" value="${field.min ?? 1}" min="0"
                   data-action="input->form-builder#updateField"
                   data-index="${index}" data-prop="min">
          </div>
          <div class="fb-qty-col">
            <label class="fb-label">Maks</label>
            <input type="number" class="fb-input" value="${field.max ?? ""}"
                   data-action="input->form-builder#updateField"
                   data-index="${index}" data-prop="max"
                   placeholder="Pa gen limit">
          </div>
          <div class="fb-qty-col">
            <label class="fb-label">Pa</label>
            <input type="number" class="fb-input" value="${field.step_value ?? 1}" min="0.01" step="0.01"
                   data-action="input->form-builder#updateField"
                   data-index="${index}" data-prop="step_value">
          </div>
        </div>
        <div class="fb-field-row">
          <label class="fb-label">Inite <span class="fb-hint">(opsyonèl — ex: kg, pake, kopi)</span></label>
          <input type="text" class="fb-input fb-input--hint" value="${this.escAttr(field.unit || "")}"
                 data-action="input->form-builder#updateField"
                 data-index="${index}" data-prop="unit"
                 placeholder="Ex: pake, moun, kopi">
        </div>
      </div>`
    }

    return html
  }

  // ─── Repeater Field Body (container for sub-field groups) ─────
  renderRepeaterFieldBody(field, index) {
    const subFieldTypes = [
      { type: "text", icon: "ri-text", label: "Tèks" },
      { type: "number", icon: "ri-hashtag", label: "Nimewo" },
      { type: "date", icon: "ri-calendar-line", label: "Dat" },
      { type: "select", icon: "ri-list-check", label: "Lis" },
      { type: "radio", icon: "ri-radio-button-line", label: "Radyo" },
      { type: "email", icon: "ri-mail-line", label: "Imèl" },
      { type: "phone", icon: "ri-phone-line", label: "Telefòn" },
      { type: "currency", icon: "ri-money-dollar-circle-line", label: "Lajan" },
      { type: "file", icon: "ri-attachment-line", label: "Fichye" },
      { type: "checkbox", icon: "ri-checkbox-line", label: "Kaz Koche" },
      { type: "datetime", icon: "ri-calendar-schedule-line", label: "Dat & Lè" }
    ]

    const subFields = Array.isArray(field.fields) ? field.fields : []

    let subFieldsHtml = ""
    subFields.forEach((sf, sfIdx) => {
      const sfTypeInfo = subFieldTypes.find(t => t.type === sf.type) || { icon: "ri-input-method-line", label: sf.type }
      const isChoice = ["select", "radio"].includes(sf.type)

      subFieldsHtml += `
        <div class="fb-repeater-subfield">
          <div class="fb-repeater-subfield-header">
            <span class="fb-field-type-badge"><i class="${sfTypeInfo.icon}"></i> ${sfTypeInfo.label}</span>
            <div class="fb-repeater-subfield-actions">
              ${sfIdx > 0 ? `<button type="button" class="fb-btn-icon" data-action="form-builder#moveSubFieldUp" data-index="${index}" data-sub-index="${sfIdx}" title="Monte"><i class="ri-arrow-up-s-line"></i></button>` : ""}
              ${sfIdx < subFields.length - 1 ? `<button type="button" class="fb-btn-icon" data-action="form-builder#moveSubFieldDown" data-index="${index}" data-sub-index="${sfIdx}" title="Desann"><i class="ri-arrow-down-s-line"></i></button>` : ""}
              <button type="button" class="fb-btn-icon fb-btn-danger" data-action="form-builder#removeSubField" data-index="${index}" data-sub-index="${sfIdx}" title="Retire">
                <i class="ri-delete-bin-line"></i>
              </button>
            </div>
          </div>
          <div class="fb-repeater-subfield-body">
            <div class="fb-field-row">
              <label class="fb-label">Etikèt</label>
              <input type="text" class="fb-input" value="${this.escAttr(sf.label)}"
                     data-action="input->form-builder#updateSubField"
                     data-index="${index}" data-sub-index="${sfIdx}" data-prop="label"
                     placeholder="Non chan an...">
            </div>
            ${isChoice ? `
            <div class="fb-field-row">
              <label class="fb-label">Opsyon <span class="fb-hint">(separe ak virgil)</span></label>
              <input type="text" class="fb-input" value="${this.escAttr(Array.isArray(sf.options) ? sf.options.map(o => typeof o === 'string' ? o : o.label).join(', ') : (sf.options || ''))}"
                     data-action="input->form-builder#updateSubFieldOptions"
                     data-index="${index}" data-sub-index="${sfIdx}"
                     placeholder="Opsyon 1, Opsyon 2, Opsyon 3">
            </div>` : ""}
            ${sf.type === "currency" ? `
            <div class="fb-field-row">
              <label class="fb-label">Deviz</label>
              <select class="fb-input" data-action="change->form-builder#updateSubField"
                      data-index="${index}" data-sub-index="${sfIdx}" data-prop="currency">
                <option value="HTG" ${sf.currency !== "USD" ? "selected" : ""}>HTG</option>
                <option value="USD" ${sf.currency === "USD" ? "selected" : ""}>USD</option>
              </select>
            </div>` : ""}
            <div class="fb-field-row fb-field-row--inline">
              <label class="fb-toggle">
                <input type="checkbox" ${sf.required ? "checked" : ""}
                       data-action="change->form-builder#updateSubField"
                       data-index="${index}" data-sub-index="${sfIdx}" data-prop="required">
                <span class="fb-toggle-slider"></span>
                <span class="fb-toggle-label">Obligatwa</span>
              </label>
            </div>
          </div>
        </div>`
    })

    let html = `
      <div class="fb-field-body fb-field-body--repeater">
        <div class="fb-field-row">
          <label class="fb-label">Etikèt</label>
          <input type="text" class="fb-input" value="${this.escAttr(field.label)}"
                 data-action="input->form-builder#updateField"
                 data-index="${index}" data-prop="label"
                 placeholder="Ex: Enfòmasyon sou Depandan">
        </div>
        <div class="fb-repeater-settings">
          <div class="fb-qty-row">
            <div class="fb-qty-col">
              <label class="fb-label">Min Ranje</label>
              <input type="number" class="fb-input" value="${field.min_rows ?? 1}" min="0" max="20"
                     data-action="input->form-builder#updateField"
                     data-index="${index}" data-prop="min_rows">
            </div>
            <div class="fb-qty-col">
              <label class="fb-label">Maks Ranje</label>
              <input type="number" class="fb-input" value="${field.max_rows ?? 10}" min="1" max="50"
                     data-action="input->form-builder#updateField"
                     data-index="${index}" data-prop="max_rows">
            </div>
          </div>
          <div class="fb-field-row">
            <label class="fb-label">Tèks Bouton</label>
            <input type="text" class="fb-input fb-input--hint" value="${this.escAttr(field.add_button_text || '+ Ajoute yon lòt')}"
                   data-action="input->form-builder#updateField"
                   data-index="${index}" data-prop="add_button_text"
                   placeholder="+ Ajoute yon lòt moun">
          </div>
        </div>

        <div class="fb-repeater-pricing">
          <div class="fb-field-row fb-field-row--inline">
            <label class="fb-toggle">
              <input type="checkbox" ${field.has_pricing ? "checked" : ""}
                     data-action="change->form-builder#toggleRepeaterPricing"
                     data-index="${index}">
              <span class="fb-toggle-slider"></span>
              <span class="fb-toggle-label"><i class="ri-price-tag-3-line"></i> Pri pa Ranje</span>
            </label>
          </div>
          ${field.has_pricing ? `
          <div class="fb-repeater-pricing-body">
            <div class="fb-repeater-pricing-mode">
              <label class="fb-radio-option">
                <input type="radio" name="repeater_pricing_mode_${index}" value="fixed"
                       ${field.pricing_mode !== "rules" ? "checked" : ""}
                       data-action="change->form-builder#updateRepeaterPricingMode"
                       data-index="${index}">
                <span class="fb-radio-label">Fiks — menm pri pou chak ranje</span>
              </label>
              <label class="fb-radio-option">
                <input type="radio" name="repeater_pricing_mode_${index}" value="rules"
                       ${field.pricing_mode === "rules" ? "checked" : ""}
                       data-action="change->form-builder#updateRepeaterPricingMode"
                       data-index="${index}">
                <span class="fb-radio-label">Kondisyonèl — pri baze sou done nan ranje a</span>
              </label>
            </div>

            ${field.pricing_mode !== "rules" ? `
            <div class="fb-field-row" style="margin-top: 0.35rem;">
              <label class="fb-label">Montan pa ranje <span class="fb-hint">(nan deviz sèvis la)</span></label>
              <input type="number" class="fb-input" value="${field.price_per_row ?? 0}" min="0" step="0.01"
                     data-action="input->form-builder#updateField"
                     data-index="${index}" data-prop="price_per_row"
                     placeholder="Ex: 405.00">
            </div>
            ` : `
            <div class="fb-repeater-rules">
              <div class="fb-repeater-rules-title">
                <i class="ri-git-branch-line"></i> Règ Pri
                <span class="fb-hint">Premye règ ki matche ap detèmine pri a</span>
              </div>
              ${this.renderRepeaterPricingRules(field, index)}
              <button type="button" class="fb-logic-add-btn" data-action="form-builder#addRepeaterPricingRule" data-index="${index}">
                <i class="ri-add-line"></i> Ajoute Règ
              </button>
            </div>
            `}
          </div>
          ` : ""}
        </div>

        <div class="fb-repeater-container">
          <div class="fb-repeater-container-title">
            <i class="ri-stack-line"></i> Chan nan chak ranje
            <span class="fb-count-badge">${subFields.length}</span>
          </div>

          ${subFieldsHtml}

          ${subFields.length === 0 ? `
          <div class="fb-repeater-empty">
            <i class="ri-add-circle-line"></i>
            <p>Ajoute chan ki ap repete pou chak antre.</p>
          </div>` : ""}

          <div class="fb-repeater-add-buttons">
            ${subFieldTypes.map(t => `
              <button type="button" class="fb-add-btn fb-add-btn--mini"
                      data-action="form-builder#addSubField"
                      data-index="${index}" data-sub-type="${t.type}">
                <i class="${t.icon}"></i> ${t.label}
              </button>`).join("")}
          </div>
        </div>

        <div class="fb-field-row fb-field-row--inline">
          <label class="fb-toggle">
            <input type="checkbox" ${field.required ? "checked" : ""}
                   data-action="change->form-builder#updateField"
                   data-index="${index}" data-prop="required">
            <span class="fb-toggle-slider"></span>
            <span class="fb-toggle-label">Obligatwa (omwens 1 ranje)</span>
          </label>
        </div>
      </div>`

    return html
  }

  addSubField(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const subType = event.currentTarget.dataset.subType || "text"
    const realIdx = this.realIndex(index)
    if (realIdx < 0) return

    const fields = [...this._fields]
    const field = { ...fields[realIdx] }
    const subFields = Array.isArray(field.fields) ? [...field.fields] : []

    const labels = {
      text: "Tèks", number: "Nimewo", date: "Dat", datetime: "Dat & Lè",
      select: "Lis Dewoulan", radio: "Radyo", email: "Imèl", phone: "Telefòn",
      currency: "Lajan", file: "Fichye", checkbox: "Kaz Koche"
    }

    const subField = {
      key: `sf_${Date.now()}`,
      type: subType,
      label: labels[subType] || "Chan",
      required: false
    }

    if (["select", "radio"].includes(subType)) {
      subField.options = "Opsyon 1,Opsyon 2,Opsyon 3"
    }
    if (subType === "currency") {
      subField.currency = "HTG"
    }

    subFields.push(subField)
    field.fields = subFields
    fields[realIdx] = field
    this._fields = fields
    this.render()
  }

  removeSubField(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const subIndex = parseInt(event.currentTarget.dataset.subIndex)
    const realIdx = this.realIndex(index)
    if (realIdx < 0) return

    const fields = [...this._fields]
    const field = { ...fields[realIdx] }
    const subFields = [...(field.fields || [])]
    subFields.splice(subIndex, 1)
    field.fields = subFields
    fields[realIdx] = field
    this._fields = fields
    this.render()
  }

  moveSubFieldUp(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const subIndex = parseInt(event.currentTarget.dataset.subIndex)
    const realIdx = this.realIndex(index)
    if (realIdx < 0 || subIndex === 0) return

    const fields = [...this._fields]
    const field = { ...fields[realIdx] }
    const subFields = [...(field.fields || [])];
    [subFields[subIndex - 1], subFields[subIndex]] = [subFields[subIndex], subFields[subIndex - 1]]
    field.fields = subFields
    fields[realIdx] = field
    this._fields = fields
    this.render()
  }

  moveSubFieldDown(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const subIndex = parseInt(event.currentTarget.dataset.subIndex)
    const realIdx = this.realIndex(index)
    if (realIdx < 0) return

    const fields = [...this._fields]
    const field = { ...fields[realIdx] }
    const subFields = [...(field.fields || [])]
    if (subIndex >= subFields.length - 1) return;
    [subFields[subIndex], subFields[subIndex + 1]] = [subFields[subIndex + 1], subFields[subIndex]]
    field.fields = subFields
    fields[realIdx] = field
    this._fields = fields
    this.render()
  }

  updateSubField(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const subIndex = parseInt(event.currentTarget.dataset.subIndex)
    const prop = event.currentTarget.dataset.prop
    const value = event.currentTarget.type === "checkbox" ? event.currentTarget.checked : event.currentTarget.value
    const realIdx = this.realIndex(index)
    if (realIdx < 0) return

    const fields = [...this._fields]
    const field = { ...fields[realIdx] }
    const subFields = [...(field.fields || [])]
    subFields[subIndex] = { ...subFields[subIndex], [prop]: value }

    // Auto-generate key from label
    if (prop === "label") {
      subFields[subIndex].key = value.toLowerCase()
        .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
        .replace(/[^a-z0-9]+/g, "_")
        .replace(/^_|_$/g, "")
        || `sf_${subIndex}`
    }

    field.fields = subFields
    fields[realIdx] = field
    this._fields = fields
    this.syncJson()
    this.renderPreview()
  }

  updateSubFieldOptions(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const subIndex = parseInt(event.currentTarget.dataset.subIndex)
    const realIdx = this.realIndex(index)
    if (realIdx < 0) return

    const optStr = event.currentTarget.value
    const options = optStr.split(",").map(s => s.trim()).filter(Boolean).map(s => ({ label: s, value: s }))

    const fields = [...this._fields]
    const field = { ...fields[realIdx] }
    const subFields = [...(field.fields || [])]
    subFields[subIndex] = { ...subFields[subIndex], options }
    field.fields = subFields
    fields[realIdx] = field
    this._fields = fields
    this.syncJson()
    this.renderPreview()
  }

  toggleRepeaterPricing(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const realIdx = this.realIndex(index)
    if (realIdx < 0) return

    const fields = [...this._fields]
    const field = { ...fields[realIdx] }
    field.has_pricing = !field.has_pricing
    if (field.has_pricing) {
      if (field.price_per_row == null) field.price_per_row = 0
      if (!field.pricing_mode) field.pricing_mode = "fixed"
    } else {
      delete field.has_pricing
      delete field.price_per_row
      delete field.pricing_mode
      delete field.pricing_rules
    }
    fields[realIdx] = field
    this._fields = fields
    this.render()
  }

  updateRepeaterPricingMode(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const mode = event.currentTarget.value
    const realIdx = this.realIndex(index)
    if (realIdx < 0) return

    const fields = [...this._fields]
    const field = { ...fields[realIdx] }
    field.pricing_mode = mode

    if (mode === "rules" && (!field.pricing_rules || !field.pricing_rules.length)) {
      // Seed with a default rule
      field.pricing_rules = [
        { condition: "default", price: field.price_per_row || 0, label: "Pri pa Defo" }
      ]
    }

    fields[realIdx] = field
    this._fields = fields
    this.render()
  }

  renderRepeaterPricingRules(field, index) {
    const rules = Array.isArray(field.pricing_rules) ? field.pricing_rules : []
    const subFields = Array.isArray(field.fields) ? field.fields : []

    // Operators available for pricing rules
    const operators = [
      { value: "equals", label: "egal a" },
      { value: "not_equals", label: "pa egal a" },
      { value: "greater_than", label: "pi gran pase" },
      { value: "less_than", label: "pi piti pase" },
      { value: "age_less_than", label: "laj < (pou dat)" },
      { value: "age_greater_than_or_equal", label: "laj ≥ (pou dat)" }
    ]

    let html = ""
    rules.forEach((rule, rIdx) => {
      const isDefault = rule.condition === "default"

      html += `<div class="fb-repeater-rule ${isDefault ? 'fb-repeater-rule--default' : ''}">
        <div class="fb-repeater-rule-header">
          ${isDefault
            ? `<span class="fb-repeater-rule-badge fb-repeater-rule-badge--default">SINON</span>`
            : `<span class="fb-repeater-rule-badge">SI</span>`
          }
          <button type="button" class="fb-btn-icon fb-btn-danger" data-action="form-builder#removeRepeaterPricingRule"
                  data-index="${index}" data-rule-index="${rIdx}" title="Retire">
            <i class="ri-close-line"></i>
          </button>
        </div>`

      if (!isDefault) {
        // Sub-field selector
        html += `
          <div class="fb-repeater-rule-condition">
            <select class="fb-input" data-action="change->form-builder#updateRepeaterPricingRule"
                    data-index="${index}" data-rule-index="${rIdx}" data-prop="field">
              <option value="">— Chwazi chan —</option>
              ${subFields.map(sf => `<option value="${sf.key}" ${rule.field === sf.key ? "selected" : ""}>${this.escHtml(sf.label)} (${sf.type})</option>`).join("")}
            </select>
            <select class="fb-input" data-action="change->form-builder#updateRepeaterPricingRule"
                    data-index="${index}" data-rule-index="${rIdx}" data-prop="operator">
              ${operators.map(op => `<option value="${op.value}" ${rule.operator === op.value ? "selected" : ""}>${op.label}</option>`).join("")}
            </select>
            <input type="text" class="fb-input" value="${this.escAttr(rule.value || '')}"
                   data-action="input->form-builder#updateRepeaterPricingRule"
                   data-index="${index}" data-rule-index="${rIdx}" data-prop="value"
                   placeholder="Valè...">
          </div>`
      }

      // Price + label
      html += `
        <div class="fb-repeater-rule-price">
          <div class="fb-qty-col">
            <label class="fb-label">Pri</label>
            <input type="number" class="fb-input" value="${rule.price ?? 0}" min="0" step="0.01"
                   data-action="input->form-builder#updateRepeaterPricingRule"
                   data-index="${index}" data-rule-index="${rIdx}" data-prop="price"
                   placeholder="0.00">
          </div>
          <div class="fb-qty-col" style="flex: 2;">
            <label class="fb-label">Etikèt <span class="fb-hint">(pou resi)</span></label>
            <input type="text" class="fb-input" value="${this.escAttr(rule.label || '')}"
                   data-action="input->form-builder#updateRepeaterPricingRule"
                   data-index="${index}" data-rule-index="${rIdx}" data-prop="label"
                   placeholder="Ex: Timoun (< 15 an)">
          </div>
        </div>
      </div>`
    })

    return html
  }

  addRepeaterPricingRule(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const realIdx = this.realIndex(index)
    if (realIdx < 0) return

    const fields = [...this._fields]
    const field = { ...fields[realIdx] }
    const rules = Array.isArray(field.pricing_rules) ? [...field.pricing_rules] : []

    // Insert new conditional rule before the default rule (if any)
    const defaultIdx = rules.findIndex(r => r.condition === "default")
    const newRule = { field: "", operator: "equals", value: "", price: 0, label: "" }

    if (defaultIdx >= 0) {
      rules.splice(defaultIdx, 0, newRule)
    } else {
      rules.push(newRule)
      // Also ensure there's a default fallback
      rules.push({ condition: "default", price: 0, label: "Pri pa Defo" })
    }

    field.pricing_rules = rules
    fields[realIdx] = field
    this._fields = fields
    this.render()
  }

  removeRepeaterPricingRule(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const ruleIndex = parseInt(event.currentTarget.dataset.ruleIndex)
    const realIdx = this.realIndex(index)
    if (realIdx < 0) return

    const fields = [...this._fields]
    const field = { ...fields[realIdx] }
    const rules = [...(field.pricing_rules || [])]
    rules.splice(ruleIndex, 1)

    // Ensure at least a default rule remains
    if (!rules.find(r => r.condition === "default")) {
      rules.push({ condition: "default", price: 0, label: "Pri pa Defo" })
    }

    field.pricing_rules = rules
    fields[realIdx] = field
    this._fields = fields
    this.render()
  }

  updateRepeaterPricingRule(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const ruleIndex = parseInt(event.currentTarget.dataset.ruleIndex)
    const prop = event.currentTarget.dataset.prop
    let value = event.currentTarget.value
    const realIdx = this.realIndex(index)
    if (realIdx < 0) return

    if (prop === "price") value = parseFloat(value) || 0

    const fields = [...this._fields]
    const field = { ...fields[realIdx] }
    const rules = [...(field.pricing_rules || [])]
    rules[ruleIndex] = { ...rules[ruleIndex], [prop]: value }
    field.pricing_rules = rules
    fields[realIdx] = field
    this._fields = fields
    this.syncJson()
    this.renderPreview()
  }

  toggleQuantity(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const realIdx = this.realIndex(index)
    const fields = [...this._fields]
    const field = { ...fields[realIdx] }

    field.is_quantity = !field.is_quantity
    if (field.is_quantity) {
      // Default settings
      if (!field.linked_to_field) field.linked_to_field = "__base_price__"
      if (field.min == null) field.min = 1
      if (field.step_value == null) field.step_value = 1
    } else {
      delete field.is_quantity
      delete field.linked_to_field
      delete field.unit
      delete field.min
      delete field.max
      delete field.step_value
    }

    fields[realIdx] = field
    this._fields = fields
    this.render()
  }

  // ─── Calculated Field Body (simple formula OR conditional rules) ──
  renderCalculatedFieldBody(field, index) {
    const hasLogic = Array.isArray(field.logic) && field.logic.length > 0
    const useLogic = hasLogic || field.use_logic

    // Build field key dropdown options for conditions
    const fieldKeys = this._fields
      .filter(f => !["calculated", "section", "instructional_text", "bonid_signature", "seal_placeholder"].includes(f.type))
      .map(f => `<option value="{{${f.key}}}">${this.escHtml(f.label)} (${f.key})</option>`)
      .join("")

    let html = `
      <div class="fb-field-row">
        <div class="fb-calc-mode-toggle">
          <label class="fb-toggle">
            <input type="checkbox" ${useLogic ? "checked" : ""}
                   data-action="change->form-builder#toggleCalcLogic"
                   data-index="${index}">
            <span class="fb-toggle-slider"></span>
            <span class="fb-toggle-label"><i class="ri-git-branch-line"></i> Lojik Kondisyonèl (Si/Alò)</span>
          </label>
        </div>
      </div>`

    if (!useLogic) {
      // ── Simple mode: single formula ──
      html += `
      <div class="fb-field-row">
        <label class="fb-label">Fòmil</label>
        <input type="text" class="fb-input" value="${this.escAttr(field.calculation || "")}"
               data-action="input->form-builder#updateCalculation"
               data-index="${index}" data-calc-prop="calculation"
               placeholder="Ex: {{pri_debaz}} + ({{jou_an_reta}} * 50)">
        <span class="fb-hint">Itilize <code>{{kle_chan}}</code> pou referanse chan. Fonksyon: max(), min(), round()</span>
      </div>`
    } else {
      // ── Conditional mode: rule builder ──
      const rules = field.logic || []
      html += `<div class="fb-calc-rules">`

      rules.forEach((rule, ri) => {
        const isDefault = rule.condition === "default" || rule.condition === ""
        html += `
        <div class="fb-calc-rule ${isDefault ? 'fb-calc-rule--default' : ''}">
          <div class="fb-calc-rule-header">
            <span class="fb-calc-rule-label">${isDefault ? 'SINON (pa defo)' : (ri === 0 ? 'SI' : 'SINON SI')}</span>
            <button type="button" class="fb-calc-rule-remove" data-action="form-builder#removeCalcRule"
                    data-index="${index}" data-rule-index="${ri}" title="Retire règ">
              <i class="ri-close-line"></i>
            </button>
          </div>
          ${!isDefault ? `
          <div class="fb-calc-condition">
            <input type="text" class="fb-input fb-calc-condition-input"
                   value="${this.escAttr(rule.condition || "")}"
                   data-action="input->form-builder#updateCalcRule"
                   data-index="${index}" data-rule-index="${ri}" data-rule-prop="condition"
                   placeholder="Ex: {{laj}} < 18  oswa  {{kategori}} == 'biznis'">
          </div>` : ""}
          <div class="fb-calc-formula">
            <label class="fb-label fb-label--small">${isDefault ? 'Fòmil:' : 'ALÒ:'}</label>
            <input type="text" class="fb-input"
                   value="${this.escAttr(rule.formula || "")}"
                   data-action="input->form-builder#updateCalcRule"
                   data-index="${index}" data-rule-index="${ri}" data-rule-prop="formula"
                   placeholder="Ex: {{pri_debaz}} * 0.5">
          </div>
        </div>`
      })

      html += `
        <div class="fb-calc-rule-actions">
          <button type="button" class="fb-add-fee-btn" data-action="form-builder#addCalcRule"
                  data-index="${index}">
            <i class="ri-add-line"></i> Ajoute Règ
          </button>
          ${!rules.some(r => r.condition === "default") ? `
          <button type="button" class="fb-add-fee-btn" data-action="form-builder#addCalcDefault"
                  data-index="${index}">
            <i class="ri-shield-check-line"></i> Ajoute Pa Defo
          </button>` : ""}
        </div>
      </div>`
    }

    // Currency selector
    html += `
    <div class="fb-field-row">
      <label class="fb-label">Deviz</label>
      <div class="fb-radio-group">
        <label class="fb-radio-option">
          <input type="radio" name="calc_currency_${index}" value="HTG"
                 ${field.currency !== "USD" ? "checked" : ""}
                 data-action="change->form-builder#updateCalculation"
                 data-index="${index}" data-calc-prop="currency">
          <span class="fb-radio-label">HTG</span>
        </label>
        <label class="fb-radio-option">
          <input type="radio" name="calc_currency_${index}" value="USD"
                 ${field.currency === "USD" ? "checked" : ""}
                 data-action="change->form-builder#updateCalculation"
                 data-index="${index}" data-calc-prop="currency">
          <span class="fb-radio-label">USD</span>
        </label>
      </div>
    </div>`

    return html
  }

  // ── Toggle between simple formula and conditional logic ──
  toggleCalcLogic(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const realIdx = this.realIndex(index)
    if (realIdx < 0) return

    const fields = [...this._fields]
    const field = { ...fields[realIdx] }

    if (event.currentTarget.checked) {
      field.use_logic = true
      if (!field.logic || !field.logic.length) {
        // Seed with one empty rule + default
        field.logic = [
          { condition: "", formula: "" },
          { condition: "default", formula: field.calculation || "" }
        ]
      }
    } else {
      field.use_logic = false
      // Keep logic data in case they toggle back
    }

    fields[realIdx] = field
    this._fields = fields
    this.render()
  }

  // ── Add a conditional rule ──
  addCalcRule(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const realIdx = this.realIndex(index)
    if (realIdx < 0) return

    const fields = [...this._fields]
    const field = { ...fields[realIdx] }
    if (!field.logic) field.logic = []

    // Insert before the "default" rule if one exists
    const defaultIdx = field.logic.findIndex(r => r.condition === "default")
    const newRule = { condition: "", formula: "" }
    if (defaultIdx >= 0) {
      field.logic.splice(defaultIdx, 0, newRule)
    } else {
      field.logic.push(newRule)
    }

    fields[realIdx] = field
    this._fields = fields
    this.render()
  }

  // ── Add a default (fallback) rule ──
  addCalcDefault(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const realIdx = this.realIndex(index)
    if (realIdx < 0) return

    const fields = [...this._fields]
    const field = { ...fields[realIdx] }
    if (!field.logic) field.logic = []

    if (!field.logic.some(r => r.condition === "default")) {
      field.logic.push({ condition: "default", formula: "" })
    }

    fields[realIdx] = field
    this._fields = fields
    this.render()
  }

  // ── Remove a conditional rule ──
  removeCalcRule(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const ruleIndex = parseInt(event.currentTarget.dataset.ruleIndex)
    const realIdx = this.realIndex(index)
    if (realIdx < 0) return

    const fields = [...this._fields]
    const field = { ...fields[realIdx] }
    if (!field.logic) return

    field.logic.splice(ruleIndex, 1)
    fields[realIdx] = field
    this._fields = fields
    this.render()
  }

  // ── Update a conditional rule's condition or formula ──
  updateCalcRule(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const ruleIndex = parseInt(event.currentTarget.dataset.ruleIndex)
    const prop = event.currentTarget.dataset.ruleProp
    const value = event.currentTarget.value
    const realIdx = this.realIndex(index)
    if (realIdx < 0) return

    const fields = [...this._fields]
    const field = { ...fields[realIdx] }
    if (!field.logic || !field.logic[ruleIndex]) return

    field.logic[ruleIndex] = { ...field.logic[ruleIndex], [prop]: value }
    fields[realIdx] = field
    this._fields = fields
    this.syncJson()
    this.renderPreview()
  }

  renderPreviewField(field) {
    const indicator = this.labelIndicator(field)
    const conditional = field.visible_if ? '<span class="fb-preview-conditional" title="Kondisyonèl"><i class="ri-git-branch-line"></i></span>' : ""
    const hintHtml = field.hint ? `<span class="fb-preview-hint">${this.escHtml(field.hint)}</span>` : ""
    const placeholder = field.placeholder || field.label
    let input = ""

    switch (field.type) {
      case "text": case "email": case "phone":
        input = `<input type="${field.type}" class="fb-preview-input" disabled placeholder="${this.escAttr(placeholder)}">`
        break
      case "number":
        if (field.is_quantity) {
          const unit = field.unit ? ` <span class="fb-preview-qty-unit">${this.escHtml(field.unit)}</span>` : ""
          const linkedLabel = field.linked_to_field === "__base_price__"
            ? "Pri Debaz"
            : (this._fields.find(f => f.key === field.linked_to_field)?.label || field.linked_to_field)
          input = `
            <div class="fb-preview-qty-wrap">
              <div class="fb-preview-qty-input">
                <button class="fb-preview-qty-btn" disabled>−</button>
                <input type="number" class="fb-preview-input fb-preview-input--qty" disabled value="${field.min ?? 1}">
                <button class="fb-preview-qty-btn" disabled>+</button>
                ${unit}
              </div>
              <div class="fb-preview-qty-formula">
                <i class="ri-close-line"></i> ${this.escHtml(linkedLabel)} = <strong>Total</strong>
              </div>
            </div>`
        } else {
          input = `<input type="number" class="fb-preview-input" disabled placeholder="${this.escAttr(placeholder)}">`
        }
        break
      case "currency": {
        const sym = field.currency === "USD" ? "$" : "G"
        input = `<div class="fb-preview-currency"><span class="fb-preview-currency-symbol">${sym}</span><input type="number" class="fb-preview-input" disabled placeholder="0.00"><span class="fb-preview-currency-code">${field.currency || "HTG"}</span></div>`
        break
      }
      case "textarea":
        input = `<textarea class="fb-preview-input fb-preview-textarea" disabled placeholder="${this.escAttr(placeholder)}"></textarea>`
        break
      case "select": {
        let selectOpts = this.parseOptions(field.options)
        if (field.sort_alpha) selectOpts = [...selectOpts].sort((a, b) => a.label.localeCompare(b.label))
        const prompt = field.placeholder || "Chwazi..."
        input = `<select class="fb-preview-input" disabled>
          <option>${this.escHtml(prompt)}</option>
          ${selectOpts.map(o => {
            const priceBadge = o.extra_price ? ` (+ ${o.extra_price})` : ""
            return `<option ${field.default_value === o.value ? 'selected' : ''}>${this.escHtml(o.label)}${priceBadge}</option>`
          }).join("")}
        </select>`
        if (field.searchable) input += `<span class="fb-preview-hint"><i class="ri-search-line"></i> Rechèch aktive</span>`
        break
      }
      case "radio": {
        let radioOpts = this.parseOptions(field.options)
        input = `<div class="fb-preview-radio-group">
          ${radioOpts.map(o => {
            const priceBadge = o.extra_price ? `<span class="fb-preview-price-badge ${o.extra_price < 0 ? 'fb-preview-price-badge--discount' : ''}">${o.extra_price > 0 ? '+' : ''}${o.extra_price}</span>` : ""
            return `<label class="fb-preview-radio"><input type="radio" name="preview_${field.key}" disabled ${field.default_value === o.value ? 'checked' : ''}> ${this.escHtml(o.label)} ${priceBadge}</label>`
          }).join("")}
        </div>`
        break
      }
      case "multi_checkbox": {
        let multiOpts = this.parseOptions(field.options)
        const multiDefaults = Array.isArray(field.default_values) ? field.default_values : []
        input = `<div class="fb-preview-checkbox-group">
          ${multiOpts.map(o => {
            const priceBadge = o.extra_price ? `<span class="fb-preview-price-badge ${o.extra_price < 0 ? 'fb-preview-price-badge--discount' : ''}">${o.extra_price > 0 ? '+' : ''}${o.extra_price}</span>` : ""
            return `<label class="fb-preview-checkbox"><input type="checkbox" disabled ${multiDefaults.includes(o.value) ? 'checked' : ''}> ${this.escHtml(o.label)} ${priceBadge}</label>`
          }).join("")}
        </div>`
        break
      }
      case "date":
        input = `<input type="date" class="fb-preview-input fb-preview-input--native">`
        break
      case "time":
        input = `<input type="time" class="fb-preview-input fb-preview-input--native">`
        break
      case "datetime":
        input = `<div class="fb-preview-datetime-row">
          <div class="fb-preview-datetime-part">
            <span class="fb-preview-datetime-label">Dat</span>
            <input type="date" class="fb-preview-input fb-preview-input--native">
          </div>
          <div class="fb-preview-datetime-part">
            <span class="fb-preview-datetime-label">Lè</span>
            <input type="time" class="fb-preview-input fb-preview-input--native">
          </div>
        </div>`
        break
      case "file":
        input = `<div class="fb-preview-file"><i class="ri-upload-2-line"></i> Chwazi fichye oswa pran foto</div>`
        break
      case "checkbox":
        input = `<label class="fb-preview-checkbox"><input type="checkbox" disabled> ${this.escHtml(field.label)}</label>`
        break
      case "calculated":
        if (field.use_logic && Array.isArray(field.logic) && field.logic.length) {
          let logicHtml = field.logic.map(r => {
            if (r.condition === "default") return `<div class="fb-preview-calc-rule"><span class="fb-preview-calc-else">SINON →</span> ${this.escHtml(r.formula || "—")}</div>`
            return `<div class="fb-preview-calc-rule"><span class="fb-preview-calc-if">SI</span> ${this.escHtml(r.condition || "?")} <span class="fb-preview-calc-then">→</span> ${this.escHtml(r.formula || "—")}</div>`
          }).join("")
          input = `<div class="fb-preview-calculated fb-preview-calculated--logic"><i class="ri-git-branch-line"></i> ${logicHtml} <small>${field.currency || "HTG"}</small></div>`
        } else {
          input = `<div class="fb-preview-calculated"><i class="ri-calculator-line"></i> <span>${this.escHtml(field.calculation || "—")}</span> <small>${field.currency || "HTG"}</small></div>`
        }
        break
      case "instructional_text": {
        const styleClass = {
          plain: "fb-preview-instruction--plain",
          info: "fb-preview-instruction--info",
          warning: "fb-preview-instruction--warning",
          success: "fb-preview-instruction--success"
        }[field.style] || "fb-preview-instruction--plain"
        const title = field.label ? `<div class="fb-preview-instruction-title">${this.escHtml(field.label)}</div>` : ""
        const desc = this.renderMarkdown(field.description || "")
        return `<div class="fb-preview-instruction ${styleClass}">
          ${title}
          <div class="fb-preview-instruction-body">${desc}</div>
        </div>`
      }
      case "address":
        return `<div class="fb-preview-address">
          <div class="fb-preview-address-title"><i class="ri-map-pin-line"></i> ${this.escHtml(field.label)}</div>
          <div class="fb-preview-address-fields">
            <div class="fb-preview-address-row">
              <label class="fb-preview-label">Seksyon Kominal</label>
              <select class="fb-preview-input" disabled><option>Chwazi...</option></select>
            </div>
            <div class="fb-preview-address-row">
              <label class="fb-preview-label">Ri / Adrès</label>
              <input type="text" class="fb-preview-input" disabled placeholder="Ri, nimewo kay...">
            </div>
            <div class="fb-preview-address-row">
              <label class="fb-preview-label">Lokalite</label>
              <input type="text" class="fb-preview-input" disabled placeholder="Katye, zòn...">
            </div>
            <div class="fb-preview-address-row">
              <label class="fb-preview-label">Depatman</label>
              <select class="fb-preview-input" disabled><option>Chwazi...</option></select>
            </div>
            <div class="fb-preview-address-row">
              <label class="fb-preview-label">Awondisman</label>
              <select class="fb-preview-input" disabled><option>Chwazi...</option></select>
            </div>
            <div class="fb-preview-address-row">
              <label class="fb-preview-label">Komin</label>
              <select class="fb-preview-input" disabled><option>Chwazi...</option></select>
            </div>
            <div class="fb-preview-address-row">
              <label class="fb-preview-label">Kòd Postal</label>
              <input type="text" class="fb-preview-input" disabled placeholder="HT0000">
            </div>
          </div>
          <div class="fb-preview-address-autofill"><i class="ri-magic-line"></i> BonID Pre-ranpli</div>
        </div>`
      case "repeater": {
        const subFields = Array.isArray(field.fields) ? field.fields : []
        if (subFields.length === 0) {
          return `<div class="fb-preview-repeater fb-preview-repeater--empty">
            <div class="fb-preview-repeater-label">${this.escHtml(field.label)}</div>
            <p style="font-size: 0.75rem; color: #9CA3AF;">Pa gen chan nan repetè a ankò.</p>
          </div>`
        }

        let rowHtml = `<div class="fb-preview-repeater-row">`
        subFields.forEach(sf => {
          const sfLabel = sf.label || sf.key
          const sfRequired = sf.required ? ' <span style="color: #EF4444;">*</span>' : ""
          let sfInput = ""
          switch (sf.type) {
            case "text": case "email": case "phone":
              sfInput = `<input type="${sf.type}" class="fb-preview-input" disabled placeholder="${this.escAttr(sfLabel)}">`;  break
            case "number":
              sfInput = `<input type="number" class="fb-preview-input" disabled placeholder="0">`;  break
            case "date":
              sfInput = `<input type="date" class="fb-preview-input" disabled>`;  break
            case "datetime":
              sfInput = `<input type="datetime-local" class="fb-preview-input" disabled>`;  break
            case "currency": {
              const sym = sf.currency === "USD" ? "$" : "G"
              sfInput = `<div class="fb-preview-currency"><span class="fb-preview-currency-symbol">${sym}</span><input type="number" class="fb-preview-input" disabled placeholder="0.00"><span class="fb-preview-currency-code">${sf.currency || "HTG"}</span></div>`;  break
            }
            case "select": {
              const opts = this.parseOptions(sf.options)
              sfInput = `<select class="fb-preview-input" disabled><option>Chwazi...</option>${opts.map(o => `<option>${this.escHtml(o.label)}</option>`).join("")}</select>`;  break
            }
            case "radio": {
              const opts = this.parseOptions(sf.options)
              sfInput = `<div class="fb-preview-radio-group">${opts.map(o => `<label class="fb-preview-radio"><input type="radio" disabled> ${this.escHtml(o.label)}</label>`).join("")}</div>`;  break
            }
            case "file":
              sfInput = `<div class="fb-preview-file" style="padding: 0.4rem 0.6rem; font-size: 0.7rem;"><i class="ri-upload-2-line"></i> Fichye</div>`;  break
            case "checkbox":
              sfInput = `<label class="fb-preview-checkbox"><input type="checkbox" disabled> ${this.escHtml(sfLabel)}</label>`;  break
            default:
              sfInput = `<input type="text" class="fb-preview-input" disabled>`
          }
          rowHtml += `<div class="fb-preview-field" style="margin-bottom: 0.5rem;">
            ${sf.type !== "checkbox" ? `<label class="fb-preview-label">${this.escHtml(sfLabel)}${sfRequired}</label>` : ""}
            ${sfInput}
          </div>`
        })
        rowHtml += `</div>`

        // Show min_rows worth of rows (just 1 for preview, with note)
        return `<div class="fb-preview-repeater">
          <label class="fb-preview-label">${this.escHtml(field.label)} ${conditional}</label>
          <div class="fb-preview-repeater-card">
            <div class="fb-preview-repeater-row-header">
              <span style="font-size: 0.7rem; font-weight: 600; color: #6B7280;">#1</span>
              <button class="fb-preview-qty-btn" disabled style="width: 20px; height: 20px; font-size: 0.65rem;"><i class="ri-delete-bin-line"></i></button>
            </div>
            ${rowHtml}
          </div>
          <button class="fb-preview-repeater-add" disabled>
            <i class="ri-add-line"></i> ${this.escHtml(field.add_button_text || "+ Ajoute yon lòt")}
          </button>
          <span class="fb-preview-hint" style="text-align: center;">Min: ${field.min_rows || 1} · Maks: ${field.max_rows || 10}</span>
        </div>`
      }
      case "section":
        return `<div class="fb-preview-section">
          <div class="fb-preview-section-title">${this.escHtml(field.label)}</div>
          ${field.description ? `<div class="fb-preview-section-desc">${this.escHtml(field.description)}</div>` : ""}
        </div>`
      case "bonid_signature":
        input = `<div class="fb-preview-signature">
          <div class="fb-preview-sig-block">
            <div class="fb-preview-sig-visual">
              <i class="ri-quill-pen-line"></i>
              <span>Siyati BonID Sitwayen</span>
            </div>
            <label class="fb-preview-checkbox fb-preview-consent">
              <input type="checkbox" disabled checked>
              <span>Mwen otorize [Patnè] itilize siyati BonID mwen pou siyen aplikasyon sa a.</span>
            </label>
          </div>
        </div>`
        break
      case "seal_placeholder":
        input = `<div class="fb-preview-seal">
          <div class="fb-preview-seal-circle">
            <i class="ri-stamp-line"></i>
            <span>Sèl Ofisyèl</span>
            <small>Ap tann apwobasyon</small>
          </div>
        </div>`
        break
      default:
        input = `<input type="text" class="fb-preview-input" disabled>`
    }

    return `<div class="fb-preview-field ${field.visible_if ? 'fb-preview-field--conditional' : ''} ${field.type === 'bonid_signature' || field.type === 'seal_placeholder' ? 'fb-preview-field--signing' : ''}">
      ${field.type !== 'bonid_signature' && field.type !== 'seal_placeholder' ? `<label class="fb-preview-label">${this.escHtml(field.label)} ${indicator} ${conditional}</label>` : ''}
      ${hintHtml}
      ${input}
    </div>`
  }

  // ─── JSON Sync ──────────────────────────────────────────
  syncJson() {
    // Strip UI-only properties (prefixed with _) before saving
    const cleanFields = this._fields.map(f => {
      const clean = { ...f }
      Object.keys(clean).forEach(k => { if (k.startsWith("_")) delete clean[k] })
      return clean
    })
    const data = {
      fields: cleanFields,
      steps: this._steps.length ? this._steps : undefined,
      price_metadata: this._priceMeta && Object.keys(this._priceMeta).length
        ? this._priceMeta : undefined
    }
    if (!data.steps) delete data.steps
    if (!data.price_metadata) delete data.price_metadata
    this.structureJsonTarget.value = JSON.stringify(data)
  }

  // ─── Step-aware helpers ─────────────────────────────────

  // Returns fields visible in the current active step (or all if no steps)
  visibleFields() {
    if (!this._steps.length) return this._fields
    return this._fields.filter(f => f.step === this._activeStep)
  }

  // Maps a visible-index to the real index in fieldsValue
  realIndex(visibleIdx) {
    const visible = this.visibleFields()
    if (visibleIdx < 0 || visibleIdx >= visible.length) return -1
    const targetField = visible[visibleIdx]
    return this._fields.indexOf(targetField)
  }

  // ─── Type Helpers ──────────────────────────────────────
  typeIcon(type) {
    const icons = {
      text: "ri-text", number: "ri-hashtag", currency: "ri-money-dollar-circle-line",
      email: "ri-mail-line", phone: "ri-phone-line", select: "ri-list-check",
      radio: "ri-radio-button-line", multi_checkbox: "ri-checkbox-multiple-line",
      checkbox: "ri-checkbox-line", file: "ri-attachment-line", date: "ri-calendar-line",
      time: "ri-time-line", textarea: "ri-file-text-line", calculated: "ri-calculator-line",
      address: "ri-map-pin-line", instructional_text: "ri-chat-quote-line", section: "ri-separator",
      bonid_signature: "ri-quill-pen-line", seal_placeholder: "ri-stamp-line",
      repeater: "ri-repeat-line",
      datetime: "ri-calendar-schedule-line"
    }
    return `<i class="${icons[type] || "ri-input-method-line"}"></i>`
  }

  typeLabel(type) {
    const labels = {
      text: "Tèks", number: "Nimewo", currency: "Lajan",
      email: "Imèl", phone: "Telefòn", select: "Lis Dewoulan",
      radio: "Radyo", multi_checkbox: "Plizyè Chwa",
      checkbox: "Kaz Koche", file: "Fichye", date: "Dat", time: "Lè",
      textarea: "Tèks Long",
      calculated: "Kalkile", address: "Adrès", instructional_text: "Enstriksyon", section: "Seksyon",
      bonid_signature: "Siyati BonID", seal_placeholder: "Sèl Ofisyèl",
      repeater: "Repetè",
      datetime: "Dat & Lè"
    }
    return labels[type] || type
  }

  escAttr(str) {
    return (str || "").replace(/"/g, "&quot;").replace(/</g, "&lt;")
  }

  escHtml(str) {
    const div = document.createElement("div")
    div.textContent = str || ""
    return div.innerHTML
  }

  // ─── Select Option Chips ────────────────────────────────

  // Parse options from string ("A,B,C") or array ([{label,value}]) — returns normalized array
  parseOptions(options) {
    if (!options) return []
    if (Array.isArray(options)) {
      return options.map(o => typeof o === "string" ? { label: o, value: o } : o)
    }
    // Legacy comma-separated string — supports "Label:Value" format
    return options.split(",").map(s => s.trim()).filter(Boolean).map(s => {
      const parts = s.split(":")
      if (parts.length >= 2) {
        return { label: parts[0].trim(), value: parts.slice(1).join(":").trim() }
      }
      return { label: s, value: s }
    })
  }

  // Serialize options array back to the field
  serializeOptions(optionsArray) {
    return optionsArray
  }

  optionKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      event.stopPropagation()
      this.addOptionFromInput(event)
    }
  }

  addOptionFromInput(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const container = event.currentTarget.closest(".fb-field-row")
    const input = container.querySelector(".fb-option-input")
    const errorEl = this.element.querySelector(`[data-option-error="${index}"]`)
    const raw = input.value.trim()
    if (!raw) return

    // Validate: only one colon allowed for label:value separation
    const colonCount = (raw.match(/:/g) || []).length
    if (colonCount > 1) {
      if (errorEl) {
        errorEl.textContent = "Sèlman itilize yon sèl : pou separe non ak kòd la."
        errorEl.style.display = "block"
      }
      input.classList.add("fb-input--error")
      return
    }

    // Clear any previous error
    if (errorEl) errorEl.style.display = "none"
    input.classList.remove("fb-input--error")

    const realIdx = this.realIndex(index)
    if (realIdx < 0) return

    const fields = [...this._fields]
    const field = { ...fields[realIdx] }
    const opts = this.parseOptions(field.options)

    // Parse "label:value" format
    const parts = raw.split(":")
    if (parts.length === 2 && parts[0].trim() && parts[1].trim()) {
      opts.push({ label: parts[0].trim(), value: parts[1].trim() })
    } else {
      opts.push({ label: raw, value: raw })
    }

    field.options = this.serializeOptions(opts)
    fields[realIdx] = field
    this._fields = fields
    input.value = ""
    this.render()
  }

  removeOption(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const optionIndex = parseInt(event.currentTarget.dataset.optionIndex)
    const realIdx = this.realIndex(index)
    if (realIdx < 0) return

    const fields = [...this._fields]
    const field = { ...fields[realIdx] }
    const opts = this.parseOptions(field.options)

    // Also remove from defaults if present
    const removed = opts[optionIndex]
    if (removed && field.default_values) {
      field.default_values = field.default_values.filter(v => v !== removed.value)
    }
    if (removed && field.default_value === removed.value) {
      field.default_value = ""
    }

    opts.splice(optionIndex, 1)
    field.options = this.serializeOptions(opts)
    fields[realIdx] = field
    this._fields = fields
    this.render()
  }

  // ── Toggle default value on a chip ──
  toggleDefault(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const optionIndex = parseInt(event.currentTarget.dataset.optionIndex)
    const realIdx = this.realIndex(index)
    if (realIdx < 0) return

    const fields = [...this._fields]
    const field = { ...fields[realIdx] }
    const opts = this.parseOptions(field.options)
    const opt = opts[optionIndex]
    if (!opt) return

    if (field.type === "multi_checkbox") {
      // Multi: toggle in/out of default_values array
      const defaults = Array.isArray(field.default_values) ? [...field.default_values] : []
      const idx = defaults.indexOf(opt.value)
      if (idx >= 0) {
        defaults.splice(idx, 1)
      } else {
        defaults.push(opt.value)
      }
      field.default_values = defaults
    } else {
      // Single (select/radio): toggle on/off
      field.default_value = field.default_value === opt.value ? "" : opt.value
    }

    fields[realIdx] = field
    this._fields = fields
    this.render()
  }

  // ── Update price on a specific option ──
  updateOptionPrice(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    const optionIndex = parseInt(event.currentTarget.dataset.optionIndex)
    const realIdx = this.realIndex(index)
    if (realIdx < 0) return

    const price = parseFloat(event.currentTarget.value) || 0
    const fields = [...this._fields]
    const field = { ...fields[realIdx] }
    const opts = this.parseOptions(field.options)
    if (!opts[optionIndex]) return

    opts[optionIndex].extra_price = price
    field.options = this.serializeOptions(opts)
    fields[realIdx] = field
    this._fields = fields
    this.syncJson()
    this.renderPreview()
  }

  // ── Clear all options ──
  clearAllOptions(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const realIdx = this.realIndex(index)
    if (realIdx < 0) return

    const fields = [...this._fields]
    const field = { ...fields[realIdx] }
    field.options = []
    field.default_value = ""
    field.default_values = []
    fields[realIdx] = field
    this._fields = fields
    this.render()
  }

  // ── Switch choice mode (select ↔ radio ↔ multi_checkbox) ──
  switchChoiceMode(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index)
    const mode = event.currentTarget.dataset.mode
    const realIdx = this.realIndex(index)
    if (realIdx < 0) return

    const fields = [...this._fields]
    const field = { ...fields[realIdx] }

    // Don't do anything if already the same mode
    if (field.type === mode) return

    // Switching from single to multi or vice versa — migrate defaults
    if (mode === "multi_checkbox" && field.default_value) {
      field.default_values = [field.default_value]
      delete field.default_value
    } else if (mode !== "multi_checkbox" && field.default_values) {
      field.default_value = field.default_values[0] || ""
      delete field.default_values
    }

    field.type = mode
    fields[realIdx] = field
    this._fields = fields
    this.render()
  }

  // Basic markdown: **bold**, *italic*, `code`
  renderMarkdown(str) {
    let html = this.escHtml(str)
    html = html.replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
    html = html.replace(/\*(.+?)\*/g, "<em>$1</em>")
    html = html.replace(/`(.+?)`/g, "<code>$1</code>")
    html = html.replace(/\n/g, "<br>")
    return html
  }
}
