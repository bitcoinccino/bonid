import { Controller } from "@hotwired/stimulus"

/**
 * ServiceFormController — Citizen-facing dynamic form wizard
 * ==========================================================
 * Renders a partner's schema as a multi-step form with:
 *   - Step navigation with progress bar
 *   - Auto-skip pages when all fields are conditionally hidden
 *   - Auto-save on step change (AJAX)
 *   - Conditional logic (visible_if branching + OR/AND + nested)
 *   - Conditional required (skip validation for hidden fields)
 *   - Calculated fields (real-time)
 *   - Required field validation per step
 *   - File upload handling
 *   - BonID signature consent
 */
export default class extends Controller {
  static targets = [
    "stepPanel",    // Each step's field container
    "progressBar",  // The progress indicator
    "stepLabel",    // Step number text
    "prevBtn",      // Previous step button
    "nextBtn",      // Next step button
    "submitBtn",    // Final submit button
    "saveStatus",   // "Saved at HH:MM" indicator
    "form",         // The <form> element
    "fieldWrap",    // Individual field wrappers (for conditional logic)
    "pricingCart",  // Pricing summary container
    "cartLines",   // Line items inside pricing cart
    "cartTotal"    // Total line
  ]

  static values = {
    currentStep: { type: Number, default: 0 },
    totalSteps: { type: Number, default: 1 },
    applicationId: Number,
    autoSaveUrl: String,
    savedData: { type: Object, default: {} },
    autoFill: { type: Object, default: {} },
    schema: { type: Array, default: [] },  // fields_by_step array
    pricing: { type: Object, default: {} } // pricing config
  }

  connect() {
    this.autoSaveTimer = null
    this.isDirty = false
    this.showStep(this.currentStepValue)
    this.applyAutoFill()
    this.evaluateAllConditions()
    this.computeAllCalculated()
    this.updatePricingCart()
    this.startAutoSave()
  }

  disconnect() {
    if (this.autoSaveTimer) clearInterval(this.autoSaveTimer)
  }

  // ── Step Navigation ──────────────────────────────────

  nextStep() {
    if (!this.validateCurrentStep()) return

    // Save before advancing
    this.saveStepData()

    if (this.currentStepValue < this.totalStepsValue - 1) {
      // Find the next non-skippable step
      let nextIdx = this.currentStepValue + 1
      while (nextIdx < this.totalStepsValue && this.isStepSkippable(nextIdx)) {
        nextIdx++
      }

      // If all remaining steps are skippable, go to the last step (submit)
      if (nextIdx >= this.totalStepsValue) {
        nextIdx = this.totalStepsValue - 1
      }

      this.currentStepValue = nextIdx
      this.showStep(this.currentStepValue)
      window.scrollTo({ top: 0, behavior: "smooth" })
    }
  }

  prevStep() {
    this.saveStepData()

    if (this.currentStepValue > 0) {
      // Find the previous non-skippable step
      let prevIdx = this.currentStepValue - 1
      while (prevIdx > 0 && this.isStepSkippable(prevIdx)) {
        prevIdx--
      }

      this.currentStepValue = prevIdx
      this.showStep(this.currentStepValue)
      window.scrollTo({ top: 0, behavior: "smooth" })
    }
  }

  goToStep(event) {
    const step = parseInt(event.currentTarget.dataset.step, 10)
    if (step <= this.currentStepValue) {
      this.saveStepData()
      this.currentStepValue = step
      this.showStep(step)
    }
  }

  /**
   * Check if a step should be auto-skipped because ALL its
   * conditional fields are hidden (and it has no unconditional fields).
   */
  isStepSkippable(stepIndex) {
    const panel = this.stepPanelTargets[stepIndex]
    if (!panel) return false

    const fieldWraps = panel.querySelectorAll("[data-service-form-target='fieldWrap']")
    if (fieldWraps.length === 0) return true // empty step = skip

    // A step is skippable if EVERY field in it is conditionally hidden
    let allHidden = true
    fieldWraps.forEach(wrap => {
      if (wrap.dataset.conditionHidden !== "true") {
        allHidden = false
      }
    })

    return allHidden
  }

  showStep(index) {
    // Show/hide step panels
    this.stepPanelTargets.forEach((panel, i) => {
      panel.style.display = i === index ? "block" : "none"
    })

    // Update progress bar
    this.updateProgress(index)

    // Update navigation buttons
    if (this.hasPrevBtnTarget) {
      this.prevBtnTarget.style.display = index === 0 ? "none" : "inline-flex"
    }
    if (this.hasNextBtnTarget) {
      this.nextBtnTarget.style.display = index === this.totalStepsValue - 1 ? "none" : "inline-flex"
    }
    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.style.display = index === this.totalStepsValue - 1 ? "inline-flex" : "none"
    }

    // Update step label
    if (this.hasStepLabelTarget) {
      this.stepLabelTarget.textContent = `Etap ${index + 1} sou ${this.totalStepsValue}`
    }

    // Re-evaluate conditions for the visible step
    this.evaluateAllConditions()
    this.computeAllCalculated()
  }

  updateProgress(index) {
    if (!this.hasProgressBarTarget) return

    const dots = this.progressBarTarget.querySelectorAll(".sf-progress-dot")
    const lines = this.progressBarTarget.querySelectorAll(".sf-progress-line")

    dots.forEach((dot, i) => {
      const skippable = this.isStepSkippable(i)
      dot.classList.toggle("sf-progress-dot--completed", i < index)
      dot.classList.toggle("sf-progress-dot--active", i === index)
      dot.classList.toggle("sf-progress-dot--upcoming", i > index)
      dot.classList.toggle("sf-progress-dot--skipped", skippable && i !== index)
    })

    lines.forEach((line, i) => {
      line.classList.toggle("sf-progress-line--completed", i < index)
    })
  }

  // ── Auto-Fill from BonID Profile ─────────────────────

  applyAutoFill() {
    const fill = this.autoFillValue
    if (!fill || Object.keys(fill).length === 0) return

    Object.entries(fill).forEach(([key, value]) => {
      const input = this.element.querySelector(`[name="form_data[${key}]"]`)
      if (input && !input.value && value) {
        input.value = value
        input.classList.add("sf-autofilled")
      }
    })
  }

  // ── Conditional Logic (visible_if) ───────────────────
  //
  // Supports 3 formats:
  //   1. Single rule (legacy):     { field, operator, value }
  //   2. AND (all_of):             { all_of: [ {rule}, {rule} ] }
  //   3. OR  (any_of):             { any_of: [ {rule}, {rule} ] }
  //   4. Array of rules (AND):     [ {rule}, {rule} ]

  evaluateAllConditions() {
    this.fieldWrapTargets.forEach(wrap => {
      const rules = wrap.dataset.visibleIf
      if (!rules) return

      try {
        const conditions = JSON.parse(rules)
        const visible = this.evaluateConditionGroup(conditions)
        wrap.style.display = visible ? "block" : "none"
        wrap.dataset.conditionHidden = visible ? "false" : "true"

        // Programmatic required deactivation: when a field is hidden,
        // remove required/aria-required so it doesn't block submission.
        // Restore when visible again.
        const inputs = wrap.querySelectorAll("input, select, textarea")
        inputs.forEach(input => {
          if (!visible) {
            // Store original required state before removing
            if (input.hasAttribute("required") || input.getAttribute("aria-required") === "true") {
              input.dataset.wasRequired = "true"
            }
            input.removeAttribute("required")
            input.setAttribute("aria-required", "false")
            input.setAttribute("aria-hidden", "true")
          } else {
            // Restore required state
            if (input.dataset.wasRequired === "true" || wrap.dataset.required === "true") {
              input.setAttribute("aria-required", "true")
            }
            input.removeAttribute("aria-hidden")
          }
        })
      } catch (e) {
        // Invalid JSON — show field
        wrap.style.display = "block"
        wrap.dataset.conditionHidden = "false"
      }
    })
  }

  /**
   * Evaluate a condition group — handles all formats:
   *   - Single rule object: { field, operator, value }
   *   - Array of rules (AND): [ {rule}, {rule} ]
   *   - all_of (AND): { all_of: [...] }
   *   - any_of (OR):  { any_of: [...] }
   */
  evaluateConditionGroup(conditions) {
    // Array of rules → AND logic (legacy + simple)
    if (Array.isArray(conditions)) {
      return conditions.every(rule => this.evaluateSingleCondition(rule))
    }

    // Object with any_of → OR logic
    if (conditions.any_of && Array.isArray(conditions.any_of)) {
      return conditions.any_of.some(rule => this.evaluateConditionGroup(rule))
    }

    // Object with all_of → AND logic
    if (conditions.all_of && Array.isArray(conditions.all_of)) {
      return conditions.all_of.every(rule => this.evaluateConditionGroup(rule))
    }

    // Single rule object { field, operator, value }
    if (conditions.field && conditions.operator) {
      return this.evaluateSingleCondition(conditions)
    }

    // Unknown format — show field
    return true
  }

  /**
   * Evaluate a single condition rule: { field, operator, value }
   */
  evaluateSingleCondition(rule) {
    const input = this.element.querySelector(`[name="form_data[${rule.field}]"]`)
    const value = input ? input.value : ""

    switch (rule.operator) {
      case "equals":       return value === rule.value
      case "not_equals":   return value !== rule.value
      case "greater_than": return parseFloat(value) > parseFloat(rule.value)
      case "less_than":    return parseFloat(value) < parseFloat(rule.value)
      case "contains":     return value.toLowerCase().includes((rule.value || "").toLowerCase())
      case "is_empty":     return !value || value.trim() === ""
      case "is_not_empty": return value && value.trim() !== ""
      default: return true
    }
  }

  // When any field changes, re-evaluate conditions and calculations
  fieldChanged() {
    this.evaluateAllConditions()
    this.computeAllCalculated()
    this.updatePricingCart()
    this.isDirty = true
  }

  // ── DateTime split (date + time → hidden combined field) ──
  datetimePartChanged(event) {
    const targetKey = event.currentTarget.dataset.datetimeTarget
    if (!targetKey) return

    const hidden = this.element.querySelector(`#${targetKey}`)
    if (!hidden) return

    const dateInput = this.element.querySelector(`#${targetKey}_date`)
    const timeInput = this.element.querySelector(`#${targetKey}_time`)
    if (!dateInput || !timeInput) return

    const dateVal = dateInput.value
    const timeVal = timeInput.value

    if (dateVal && timeVal) {
      hidden.value = `${dateVal}T${timeVal}`
    } else if (dateVal) {
      hidden.value = `${dateVal}T00:00`
    } else {
      hidden.value = ""
    }

    this.fieldChanged()
  }

  // ── Quantity Stepper ─────────────────────────────────

  incrementQty(event) {
    const fieldKey = event.currentTarget.dataset.field
    const max = event.currentTarget.dataset.max ? parseFloat(event.currentTarget.dataset.max) : Infinity
    const step = parseFloat(event.currentTarget.dataset.step) || 1
    const input = this.element.querySelector(`#field_${fieldKey}`)
    if (!input) return

    const current = parseFloat(input.value) || 0
    const next = current + step
    if (next <= max) {
      input.value = next
      this.fieldChanged()
    }
  }

  decrementQty(event) {
    const fieldKey = event.currentTarget.dataset.field
    const min = parseFloat(event.currentTarget.dataset.min) || 1
    const input = this.element.querySelector(`#field_${fieldKey}`)
    if (!input) return

    const current = parseFloat(input.value) || 0
    const step = parseFloat(input.step) || 1
    const next = current - step
    if (next >= min) {
      input.value = next
      this.fieldChanged()
    }
  }

  // ── Live Pricing Cart ───────────────────────────────

  updatePricingCart() {
    if (!this.hasPricingCartTarget) return
    const p = this.pricingValue
    if (!p || p.pricing_type === "free") return
    // Allow base_cents=0 when there are priced options (e.g., ticket types)
    if (!p.base_cents && !(p.priced_fields && p.priced_fields.length > 0)) return

    const data = this.collectFormData()
    const currency = p.currency || "HTG"
    const sym = currency === "USD" ? "$" : ""
    const fmt = (cents) => {
      const val = (cents / 100).toFixed(2)
      return `${sym}${parseFloat(val).toLocaleString()} ${currency}`
    }

    let lines = []
    let baseCents = p.base_cents
    let qtyMultiplier = 1
    let qtyLabel = null

    // Find quantity field linked to base price (skip if conditionally hidden)
    const qtyFields = (p.priced_fields || []).filter(f => f.is_quantity && f.linked_to_field === "__base_price__")
    const visibleQtyField = qtyFields.find(qf => {
      const input = this.element.querySelector(`#field_${qf.key}`)
      if (!input) return false
      const wrap = input.closest("[data-service-form-target='fieldWrap']")
      return !wrap || wrap.dataset.conditionHidden !== "true"
    })
    if (visibleQtyField) {
      const qf = visibleQtyField
      const qtyVal = parseFloat(data[qf.key]) || parseFloat(qf.min) || 1
      qtyMultiplier = Math.max(qtyVal, parseFloat(qf.min) || 1)
      const unit = qf.unit ? ` ${qf.unit}` : ""
      qtyLabel = qf.label
      const effectiveBase = Math.round(baseCents * qtyMultiplier)

      lines.push({
        label: qf.label || "Kantite",
        detail: `${fmt(baseCents)} × ${qtyMultiplier}${unit}`,
        amount: effectiveBase
      })
      baseCents = effectiveBase
    } else if (baseCents > 0) {
      lines.push({ label: "Pri Debaz", detail: null, amount: baseCents })
    }

    let totalCents = baseCents

    // Mandatory fees
    const fees = p.mandatory_fees || []
    fees.forEach(fee => {
      const kind = fee.kind || fee.type
      let amt = 0
      if (kind === "percent" || kind === "percentage") {
        amt = Math.round(baseCents * (fee.value || fee.amount || 0) / 100)
        lines.push({ label: `${fee.name} (${fee.value || fee.amount}%)`, detail: null, amount: amt, cls: "fee" })
      } else if (kind === "fixed") {
        amt = Math.round((fee.value || fee.amount || 0) * 100)
        lines.push({ label: fee.name, detail: null, amount: amt, cls: "fee" })
      }
      totalCents += amt
    })

    // Optional field add-ons (choice fields with pricing)
    const pricedChoices = (p.priced_fields || []).filter(f => !f.is_quantity && f.type !== "repeater" && f.options)
    // Find quantity fields linked to choice fields (not base price)
    const choiceQtyFields = (p.priced_fields || []).filter(f => f.is_quantity && f.linked_to_field && f.linked_to_field !== "__base_price__")

    pricedChoices.forEach(pf => {
      const chosen = data[pf.key]
      if (!chosen) return
      const chosenValues = Array.isArray(chosen) ? chosen : [chosen]
      const options = Array.isArray(pf.options) ? pf.options : (typeof pf.options === "string" ? pf.options.split(",").map(o => {
        const parts = o.split(":")
        return { value: parts[1] || parts[0], label: parts[0], extra_price: 0 }
      }) : [])

      // Check if a quantity field is linked to this choice field
      const linkedQty = choiceQtyFields.find(qf => qf.linked_to_field === pf.key)
      let qtyMulti = 1
      let qtyUnit = ""
      if (linkedQty) {
        const qtyVal = parseFloat(data[linkedQty.key]) || parseFloat(linkedQty.min) || 1
        qtyMulti = Math.max(qtyVal, parseFloat(linkedQty.min) || 1)
        qtyUnit = linkedQty.unit ? ` ${linkedQty.unit}` : ""
      }

      options.forEach(opt => {
        if (!opt || !chosenValues.includes(opt.value)) return
        const extraPer = Math.round((parseFloat(opt.extra_price) || 0) * 100)
        if (extraPer === 0) return
        const extra = extraPer * qtyMulti
        const cls = extra < 0 ? "discount" : "addon"
        const detail = qtyMulti > 1 ? `${fmt(extraPer)} × ${qtyMulti}${qtyUnit}` : null
        lines.push({ label: `${pf.label}: ${opt.label}`, detail, amount: extra, cls })
        totalCents += extra
      })
    })

    // Repeater price-per-row (fixed or conditional rules)
    const pricedRepeaters = (p.priced_fields || []).filter(f => f.type === "repeater" && f.has_pricing)
    pricedRepeaters.forEach(pf => {
      const container = this.element.querySelector(`[data-repeater-key="${pf.key}"]`)
      if (!container) return
      const wrap = container.closest("[data-service-form-target='fieldWrap']")
      if (wrap && wrap.dataset.conditionHidden === "true") return

      const rows = container.querySelectorAll("[data-repeater-row]")
      if (rows.length === 0) return

      if (pf.pricing_mode === "rules" && Array.isArray(pf.pricing_rules)) {
        // Conditional rules — evaluate per row
        let repeaterTotal = 0
        const breakdown = {} // { label: { count, cents } }

        rows.forEach(row => {
          // Collect sub-field values from this row
          const rowData = {}
          row.querySelectorAll("[name]").forEach(input => {
            const match = input.name.match(/\[\w+\]\[(\w+)\]$/)
            if (match) {
              rowData[match[1]] = input.type === "checkbox" ? (input.checked ? "true" : "false") : input.value
            }
          })

          // Evaluate rules — first match wins
          let matchedPrice = 0
          let matchedLabel = pf.label
          for (const rule of pf.pricing_rules) {
            if (rule.condition === "default") {
              matchedPrice = parseFloat(rule.price) || 0
              matchedLabel = rule.label || pf.label
              break
            }
            if (this._evaluateRepeaterRule(rule, rowData)) {
              matchedPrice = parseFloat(rule.price) || 0
              matchedLabel = rule.label || pf.label
              break
            }
          }

          const cents = Math.round(matchedPrice * 100)
          repeaterTotal += cents
          if (!breakdown[matchedLabel]) breakdown[matchedLabel] = { count: 0, cents }
          breakdown[matchedLabel].count++
        })

        // Add breakdown lines
        Object.entries(breakdown).forEach(([label, info]) => {
          lines.push({
            label: `${pf.label}: ${label}`,
            detail: `${fmt(info.cents)} × ${info.count}`,
            amount: info.cents * info.count,
            cls: "repeater"
          })
        })
        totalCents += repeaterTotal
      } else {
        // Fixed price per row
        const perRowCents = Math.round((parseFloat(pf.price_per_row) || 0) * 100)
        if (perRowCents === 0) return
        const rowCount = rows.length
        const repeaterTotal = perRowCents * rowCount
        lines.push({
          label: pf.label || "Repetè",
          detail: `${fmt(perRowCents)} × ${rowCount} ranje`,
          amount: repeaterTotal,
          cls: "repeater"
        })
        totalCents += repeaterTotal
      }
    })

    // Render
    let linesHtml = ""
    lines.forEach(line => {
      const clsExtra = line.cls ? ` sf-cart-line--${line.cls}` : ""
      linesHtml += `
        <div class="sf-cart-line${clsExtra}">
          <div class="sf-cart-line-label">
            ${line.label}
            ${line.detail ? `<span class="sf-cart-line-qty">${line.detail}</span>` : ""}
          </div>
          <div class="sf-cart-line-amount">${fmt(line.amount)}</div>
        </div>`
    })
    this.cartLinesTarget.innerHTML = linesHtml
    this.cartTotalTarget.innerHTML = `<span>Total</span><strong>${fmt(totalCents)}</strong>`
  }

  // ── Repeater Rule Evaluator ─────────────────────────

  _evaluateRepeaterRule(rule, rowData) {
    if (!rule.field || !rule.operator) return false
    const value = (rowData[rule.field] || "").toString()
    const expected = (rule.value || "").toString()

    switch (rule.operator) {
      case "equals":       return value === expected
      case "not_equals":   return value !== expected
      case "greater_than": return parseFloat(value) > parseFloat(expected)
      case "less_than":    return parseFloat(value) < parseFloat(expected)
      case "age_less_than": {
        const age = this._calculateAge(value)
        return age !== null && age < parseFloat(expected)
      }
      case "age_greater_than_or_equal": {
        const age = this._calculateAge(value)
        return age !== null && age >= parseFloat(expected)
      }
      default: return false
    }
  }

  _calculateAge(dateStr) {
    if (!dateStr) return null
    const dob = new Date(dateStr)
    if (isNaN(dob.getTime())) return null
    const today = new Date()
    let age = today.getFullYear() - dob.getFullYear()
    const monthDiff = today.getMonth() - dob.getMonth()
    if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < dob.getDate())) {
      age--
    }
    return age
  }

  // ── Calculated Fields ────────────────────────────────

  computeAllCalculated() {
    const allData = this.collectFormData()

    this.element.querySelectorAll("[data-calculated-formula]").forEach(el => {
      const formula = el.dataset.calculatedFormula
      const key = el.dataset.fieldKey
      if (!formula) return

      // Skip calculation if the field's wrapper is conditionally hidden
      const wrap = el.closest("[data-service-form-target='fieldWrap']")
      if (wrap && wrap.dataset.conditionHidden === "true") return

      try {
        const result = this.evaluateFormula(formula, allData)
        const currency = el.dataset.currency || "HTG"
        el.textContent = `${this.formatNumber(result)} ${currency}`

        // Also update the hidden input
        const hidden = this.element.querySelector(`[name="form_data[${key}]"]`)
        if (hidden) hidden.value = result
      } catch (e) {
        el.textContent = "—"
      }
    })
  }

  evaluateFormula(formula, data) {
    const expression = formula.replace(/[a-z_][a-z0-9_]*/gi, ref => {
      const val = data[ref]
      return val !== undefined && val !== "" ? parseFloat(val) || 0 : 0
    })
    try {
      return Math.round(Function(`"use strict"; return (${expression})`)() * 100) / 100
    } catch {
      return 0
    }
  }

  formatNumber(n) {
    return n.toLocaleString("fr-HT", { minimumFractionDigits: 0, maximumFractionDigits: 2 })
  }

  // ── Validation ───────────────────────────────────────
  //
  // Conditional Required: Only validate fields that are VISIBLE.
  // Hidden fields (data-condition-hidden="true") are always skipped,
  // even if marked as required.

  validateCurrentStep() {
    const panel = this.stepPanelTargets[this.currentStepValue]
    if (!panel) return true

    // If entire step is skippable (all fields hidden), pass validation
    if (this.isStepSkippable(this.currentStepValue)) return true

    let valid = true
    const fieldWraps = panel.querySelectorAll("[data-service-form-target='fieldWrap']")

    fieldWraps.forEach(wrap => {
      // ── Conditional Required: skip hidden fields entirely ──
      if (wrap.dataset.conditionHidden === "true") {
        // Clear any previous error state on hidden fields
        wrap.classList.remove("sf-field--error")
        const errorEl = wrap.querySelector(".sf-field-error")
        if (errorEl) errorEl.style.display = "none"
        return
      }

      const required = wrap.dataset.required === "true"
      if (!required) return

      // Check for repeater container
      const repeater = wrap.querySelector(".sf-repeater")
      if (repeater) {
        // Validate required sub-fields in each row
        const rows = repeater.querySelectorAll("[data-repeater-row]")
        let repeaterValid = rows.length > 0
        rows.forEach(row => {
          row.querySelectorAll(".sf-repeater-field input[required], .sf-repeater-field select[required]").forEach(input => {
            if (!input.value || input.value.trim() === "") {
              repeaterValid = false
              input.classList.add("sf-error-shake")
              setTimeout(() => input.classList.remove("sf-error-shake"), 500)
            }
          })
        })
        if (!repeaterValid) {
          valid = false
          wrap.classList.add("sf-field--error")
        } else {
          wrap.classList.remove("sf-field--error")
        }
        return
      }

      const input = wrap.querySelector("input, select, textarea")
      if (!input) return

      const isEmpty = !input.value || input.value.trim() === ""
      const errorEl = wrap.querySelector(".sf-field-error")

      if (isEmpty) {
        valid = false
        wrap.classList.add("sf-field--error")
        if (errorEl) errorEl.style.display = "block"
        if (!wrap.querySelector(".sf-error-shake")) {
          input.classList.add("sf-error-shake")
          setTimeout(() => input.classList.remove("sf-error-shake"), 500)
        }
      } else {
        wrap.classList.remove("sf-field--error")
        if (errorEl) errorEl.style.display = "none"
      }
    })

    // ── Cross-field datetime validation (after_field constraint) ──
    if (valid) {
      valid = this._validateDatetimeConstraints(panel, valid)
    }

    if (!valid) {
      // Scroll to first error
      const firstError = panel.querySelector(".sf-field--error")
      if (firstError) firstError.scrollIntoView({ behavior: "smooth", block: "center" })
    }

    return valid
  }

  /**
   * Validate datetime fields that have a data-after-field constraint.
   * E.g. "Dat party ya fini" must be after "Dat Party ya komanse".
   */
  _validateDatetimeConstraints(panel) {
    let valid = true

    // Find all field wraps with after_field constraint (datetime end-after-start)
    const constrainedWraps = panel.querySelectorAll("[data-after-field]")

    constrainedWraps.forEach(endWrap => {
      if (endWrap.dataset.conditionHidden === "true") return

      const afterKey = endWrap.dataset.afterField
      // Search the entire form for the start field (it may be on a different step)
      const startWrap = this.element.querySelector(`[data-field-key="${afterKey}"]`)
      if (!startWrap) return

      const endInput = endWrap.querySelector("input[type='hidden'][data-service-form-target='datetimeHidden']") || endWrap.querySelector("input[type='datetime-local']")
      const startInput = startWrap.querySelector("input[type='hidden'][data-service-form-target='datetimeHidden']") || startWrap.querySelector("input[type='datetime-local']")
      if (!endInput || !startInput) return

      // Only validate if both have values
      if (endInput.value && startInput.value) {
        const endDate = new Date(endInput.value)
        const startDate = new Date(startInput.value)

        if (endDate <= startDate) {
          valid = false
          endWrap.classList.add("sf-field--error")
          const errorEl = endWrap.querySelector(".sf-field-error")
          if (errorEl) {
            errorEl.textContent = "Dat/lè sa a dwe vin apre " + (startWrap.querySelector(".sf-label-text")?.textContent || "dat kòmanse a") + "."
            errorEl.style.display = "block"
          }
          endInput.classList.add("sf-error-shake")
          setTimeout(() => endInput.classList.remove("sf-error-shake"), 500)
        }
      }
    })

    return valid
  }

  // ── Auto-Save ────────────────────────────────────────

  startAutoSave() {
    if (!this.autoSaveUrlValue) return

    // Auto-save every 30 seconds if dirty
    this.autoSaveTimer = setInterval(() => {
      if (this.isDirty) this.performAutoSave()
    }, 30000)
  }

  saveStepData() {
    if (!this.autoSaveUrlValue || !this.isDirty) return
    this.performAutoSave()
  }

  async performAutoSave() {
    if (!this.applicationIdValue) return

    const data = this.collectFormData()
    this.isDirty = false

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
      const response = await fetch(this.autoSaveUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        body: JSON.stringify({
          application_id: this.applicationIdValue,
          form_data: data
        })
      })

      if (response.ok) {
        const result = await response.json()
        this.showSaveStatus(result.saved_at)

        // Update calculated values from server
        if (result.calculated_values) {
          Object.entries(result.calculated_values).forEach(([key, val]) => {
            const el = this.element.querySelector(`[data-field-key="${key}"]`)
            if (el) {
              const currency = el.dataset.currency || "HTG"
              el.textContent = `${this.formatNumber(val)} ${currency}`
            }
          })
        }
      }
    } catch (e) {
      console.warn("Auto-save failed:", e)
    }
  }

  showSaveStatus(time) {
    if (!this.hasSaveStatusTarget) return
    this.saveStatusTarget.textContent = `Sove a ${time}`
    this.saveStatusTarget.style.opacity = "1"
    setTimeout(() => {
      this.saveStatusTarget.style.opacity = "0.6"
    }, 2000)
  }

  // ── Data Collection ──────────────────────────────────

  collectFormData() {
    const data = {}
    this.element.querySelectorAll("[name^='form_data[']").forEach(input => {
      // Skip fields that are conditionally hidden
      const wrap = input.closest("[data-service-form-target='fieldWrap']")
      if (wrap && wrap.dataset.conditionHidden === "true") return

      // Check for repeater nested input: form_data[repeater_key][idx][sub_key]
      const repeaterMatch = input.name.match(/form_data\[(\w+)\]\[(\d+)\]\[(\w+)\]/)
      if (repeaterMatch) {
        const [, repKey, rowIdx, subKey] = repeaterMatch
        if (!data[repKey]) data[repKey] = []
        const idx = parseInt(rowIdx)
        if (!data[repKey][idx]) data[repKey][idx] = {}
        if (input.type === "checkbox") {
          data[repKey][idx][subKey] = input.checked ? "true" : "false"
        } else if (input.type !== "file") {
          data[repKey][idx][subKey] = input.value
        }
        return
      }

      // Standard flat input: form_data[key]
      const key = input.name.match(/form_data\[(\w+)\]/)?.[1]
      if (!key) return

      if (input.type === "radio") {
        if (input.checked) data[key] = input.value
      } else if (input.type === "checkbox") {
        data[key] = input.checked ? "true" : "false"
      } else if (input.type === "file") {
        // Files handled separately via multipart
      } else {
        data[key] = input.value
      }
    })

    // Clean repeater arrays — remove empty slots from sparse arrays
    Object.keys(data).forEach(key => {
      if (Array.isArray(data[key])) {
        data[key] = data[key].filter(row => row && Object.keys(row).length > 0)
      }
    })

    return data
  }

  // ── Repeater Row Management ─────────────────────────

  addRepeaterRow(event) {
    event.preventDefault()
    const repKey = event.currentTarget.dataset.repeaterKey
    const container = this.element.querySelector(`[data-repeater-key="${repKey}"]`)
    if (!container) return

    const maxRows = parseInt(container.dataset.repeaterMax) || 10
    const currentRows = container.querySelectorAll("[data-repeater-row]")
    if (currentRows.length >= maxRows) return

    const template = container.querySelector(`template[data-repeater-template="${repKey}"]`)
    if (!template) return

    const newIdx = Date.now() // unique index to avoid collisions
    const clone = template.content.cloneNode(true)

    // Replace __IDX__ placeholder with actual index
    clone.querySelectorAll("[name]").forEach(input => {
      input.name = input.name.replace(/__IDX__/g, newIdx)
    })
    clone.querySelectorAll("[id]").forEach(el => {
      el.id = el.id.replace(/__IDX__/g, newIdx)
    })
    clone.querySelectorAll("[for]").forEach(el => {
      el.htmlFor = el.htmlFor.replace(/__IDX__/g, newIdx)
    })

    // Update row number
    const rowNumEl = clone.querySelector(".sf-repeater-row-num")
    if (rowNumEl) rowNumEl.textContent = `#${currentRows.length + 1}`

    // Insert before the template element
    container.insertBefore(clone, template)

    // Update add button visibility
    this._updateRepeaterAddBtn(container, repKey)

    // Update all delete button visibility (show on all rows if > min)
    this._updateRepeaterDeleteBtns(container)

    this.isDirty = true
    this.fieldChanged()
  }

  removeRepeaterRow(event) {
    event.preventDefault()
    event.stopPropagation()
    const repKey = event.currentTarget.dataset.repeaterKey
    const container = this.element.querySelector(`[data-repeater-key="${repKey}"]`)
    if (!container) return

    const minRows = parseInt(container.dataset.repeaterMin) || 1
    const rows = container.querySelectorAll("[data-repeater-row]")
    if (rows.length <= minRows) return

    const row = event.currentTarget.closest("[data-repeater-row]")
    if (row) {
      row.style.opacity = "0"
      row.style.transform = "translateY(-8px)"
      row.style.transition = "all 0.15s ease"
      setTimeout(() => {
        row.remove()
        this._renumberRepeaterRows(container)
        this._updateRepeaterAddBtn(container, repKey)
        this._updateRepeaterDeleteBtns(container)
        this.fieldChanged()
      }, 150)
    }

    this.isDirty = true
  }

  handleRepeaterClick(event) {
    // Delegate — handled by specific button actions
  }

  _renumberRepeaterRows(container) {
    const rows = container.querySelectorAll("[data-repeater-row]")
    rows.forEach((row, i) => {
      const numEl = row.querySelector(".sf-repeater-row-num")
      if (numEl) numEl.textContent = `#${i + 1}`
    })
  }

  _updateRepeaterAddBtn(container, repKey) {
    const maxRows = parseInt(container.dataset.repeaterMax) || 10
    const currentRows = container.querySelectorAll("[data-repeater-row]")
    const addBtn = container.querySelector(`[data-action="click->service-form#addRepeaterRow"][data-repeater-key="${repKey}"]`)
    if (addBtn) {
      addBtn.style.display = currentRows.length >= maxRows ? "none" : "flex"
    }
  }

  _updateRepeaterDeleteBtns(container) {
    const minRows = parseInt(container.dataset.repeaterMin) || 1
    const rows = container.querySelectorAll("[data-repeater-row]")
    const deleteBtns = container.querySelectorAll(".sf-repeater-remove")
    deleteBtns.forEach(btn => {
      btn.style.display = rows.length <= minRows ? "none" : "block"
    })
  }

  // ── File Upload ──────────────────────────────────────

  triggerFileUpload(event) {
    const input = event.currentTarget.closest(".sf-field-wrap").querySelector("input[type='file']")
    if (input) input.click()
  }

  fileSelected(event) {
    const input = event.target
    const wrap = input.closest(".sf-field-wrap")
    const nameEl = wrap.querySelector(".sf-file-name")
    const previewEl = wrap.querySelector(".sf-file-preview")

    if (input.files.length > 0) {
      const file = input.files[0]
      if (nameEl) nameEl.textContent = file.name

      // Image preview
      if (previewEl && file.type.startsWith("image/")) {
        const reader = new FileReader()
        reader.onload = (e) => {
          previewEl.innerHTML = `<img src="${e.target.result}" style="max-width: 100%; max-height: 120px; border-radius: 6px; margin-top: 6px;">`
        }
        reader.readAsDataURL(file)
      }

      this.isDirty = true
    }
  }

  // ── Address Cascade (Haiti: Dept → Arr → Commune → Section Communale) ──

  async addressDepartmentChanged(event) {
    const deptId = event.target.value
    const prefix = event.target.dataset.addressPrefix
    const arrSelect = document.getElementById(`field_${prefix}_arrondissement`)
    const comSelect = document.getElementById(`field_${prefix}_commune`)
    const csSelect = document.getElementById(`field_${prefix}_communal_section`)

    // Reset downstream
    this._resetSelect(arrSelect, "— Chwazi —")
    this._resetSelect(comSelect, "— Chwazi —")
    this._resetSelect(csSelect, "— Chwazi —")

    if (!deptId) return

    const slug = event.target.selectedOptions[0]?.dataset?.slug || deptId
    try {
      const resp = await fetch(`/departments/${slug}/arrondissements`)
      const data = await resp.json()
      data.forEach(a => {
        const opt = new Option(a.name, a.id)
        arrSelect.add(opt)
      })
    } catch (e) { console.warn("Arrondissement fetch failed:", e) }
  }

  async addressArrondissementChanged(event) {
    const arrId = event.target.value
    const prefix = event.target.dataset.addressPrefix
    const comSelect = document.getElementById(`field_${prefix}_commune`)
    const csSelect = document.getElementById(`field_${prefix}_communal_section`)

    this._resetSelect(comSelect, "— Chwazi —")
    this._resetSelect(csSelect, "— Chwazi —")

    if (!arrId) return

    try {
      const resp = await fetch(`/arrondissements/${arrId}/communes`)
      const data = await resp.json()
      data.forEach(c => {
        const opt = new Option(c.name, c.id)
        comSelect.add(opt)
      })
    } catch (e) { console.warn("Commune fetch failed:", e) }
  }

  async addressCommuneChanged(event) {
    const comId = event.target.value
    const prefix = event.target.dataset.addressPrefix
    const csSelect = document.getElementById(`field_${prefix}_communal_section`)
    const postalInput = document.getElementById(`field_${prefix}_postal_code`)

    this._resetSelect(csSelect, "— Chwazi —")
    if (postalInput) postalInput.value = ""

    if (!comId) return

    try {
      const resp = await fetch(`/communes/${comId}/communal_sections`)
      const data = await resp.json()
      data.forEach(cs => {
        const opt = new Option(cs.name, cs.id)
        if (cs.postal_code) opt.dataset.postalCode = cs.postal_code
        csSelect.add(opt)
      })

      // Auto-fill postal code on section selection
      csSelect.addEventListener("change", () => {
        const selected = csSelect.selectedOptions[0]
        if (selected?.dataset?.postalCode && postalInput) {
          postalInput.value = selected.dataset.postalCode
        }
      }, { once: false })
    } catch (e) { console.warn("Communal section fetch failed:", e) }
  }

  _resetSelect(select, placeholder) {
    if (!select) return
    select.innerHTML = ""
    select.add(new Option(placeholder, ""))
  }
}
