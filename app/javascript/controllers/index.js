// app/javascript/controllers/index.js
// Stimulus registry only — NO visual engines here

const register = (name, loader) => {
  loader()
    .then(m => window.Stimulus.register(name, m.default))
    .catch(err => console.error(`❌ Controller failed: ${name}`, err))
}

const registerControllers = () => {
  // ───────── Core ─────────
  register("hello", () => import("./hello_controller"))
  register("flash", () => import("./flash_controller"))
  register("tooltip", () => import("./tooltip_controller"))
  register("modal-confirmation", () => import("./modal_confirmation_controller"))
  register("confirmation", () => import("./confirmation_controller"))
  register("cookie-consent", () => import("./cookie_consent_controller"))
  register("global-loading", () => import("./global_loading_controller"))

  // ───────── Forms ─────────
  register("form-handler", () => import("./form_handler_controller"))
  register("nested-form", () => import("./nested_form_controller"))
  register("prevent-blank-upload", () => import("./prevent_blank_upload_controller"))
  register("signature-pad", () => import("./signature_pad_controller"))
  register("photo", () => import("./photo_controller"))
  register("json-editor", () => import("./json_editor_controller"))
  register("json-sync", () => import("./json_sync_controller"))
  register("local-contact", () => import("./local_contact_controller"))


  // ───────── Address ─────────
  register("address", () => import("./address_controller"))
  register("birth-address", () => import("./birth_address_controller"))
  register("postal-code", () => import("./postal_code_controller"))
  register("geo-capture", () => import("./geo_capture_controller"))
  register("map", () => import("./map_controller"))
  register("partner-map", () => import("./partner_map_controller"))

  // ───────── Identity ─────────
  register("bonid-lookup", () => import("./bonid_lookup_controller"))
  register("id-switcher", () => import("./id_switcher_controller"))
  register("id-format", () => import("./id_format_controller"))
  register("reason", () => import("./reason_controller"))
  register("rejection", () => import("./rejection_controller"))

  // ───────── QR ─────────
  register("qr-modal", () => import("./qr_modal_controller"))
  register("qr-refresh", () => import("./qr_refresh_controller"))
  register("qr-rotator", () => import("./qr_rotator_controller"))
  register("qr-countdown", () => import("./qr_countdown_controller"))
  register("qr-scanner", () => import("./qr_scanner_controller"))
  register("live-selfie", () => import("./live_selfie_controller"))
  register("liveness-detector", () => import("./liveness_detector_controller"))
  register("passport-scan", () => import("./passport_scan_controller"))

  // ───────── Visitor Certificate ─────────
register("certificate-toggle", () =>
  import("./certificate_toggle_controller")
)

  // ───────── Admin / Partner ─────────
  register("le-search", () => import("./le_search_controller"))
  register("critical-alert", () => import("./critical_alert_controller"))
  register("admin-guidelines", () => import("./admin_guidelines_controller"))
  register("moderation", () => import("./moderation_controller"))
  register("submission-filter", () => import("./submission_filter_controller"))
  register("select-all", () => import("./select_all_controller"))

  register("partner-form", () => import("./partner_form_controller"))
  register("partner-sidebar", () => import("./partner_sidebar_controller"))
  register("partner-metrics", () => import("./partner_metrics_controller"))
  register("partner-scanner", () => import("./partner_scanner_controller"))
  register("api-keys", () => import("./api_keys_controller"))
  register("bank-selector", () => import("./bank_selector_controller"))
  register("banking-charts", () => import("./banking_charts_controller"))
  register("embassy-charts", () => import("./embassy_charts_controller"))
  register("branch-preview", () => import("./branch_preview_controller"))
  register("chart", () => import("./visitor_analytics_controller"))

  // ───────── Citizen ─────────
  register("dashboard", () => import("./dashboard_controller"))
  register("citizen-toggle", () => import("./citizen_toggle_controller"))
  register("entry-mode", () => import("./entry_mode_controller"))
  register("search", () => import("./search_controller"))
  register("resend", () => import("./resend_controller"))
  register("wallet-stack", () => import("./wallet_stack_controller"))
  register("emergency-contacts", () => import("./emergency_contacts_controller"))
  register("family-form", () => import("./family_form_controller"))
  register("social-handles", () => import("./social_handles_controller"))
  register("health-multiselect", () => import("./health_multiselect_controller"))
  register("complaint-form", () => import("./complaint_form_controller"))
  register("profile-review", () => import("./profile_review_controller"))
  register("faq", () => import("./faq_controller"))
  register("otp-consent", () => import("./otp_consent_controller"))
  register("consent-focus", () => import("./consent_focus_controller"))
  register("consent-liveness", () => import("./consent_liveness_controller"))

  // ───────── Wizard / Units ─────────
  register("multi-step-schema-form", () => import("./multi_step_schema_form_controller"))
  register("wizard", () => import("./wizard_controller"))
  register("submission-review", () => import("./submission_review_controller"))
  register("unit", () => import("./unit_controller"))
  register("sector", () => import("./sector_controller"))
  register("officer-unit", () => import("./officer_unit_controller"))

  // ───────── Officers / Incident Reports ─────────
  register("person", () => import("./person_controller"))
  register("evidence-camera", () => import("./evidence_camera_controller"))
  register("evidence-filmstrip", () => import("./evidence_filmstrip_controller"))

  console.info("✅ Stimulus controllers registered")
}

// Turbo-safe
document.addEventListener("turbo:load", () => {
  if (window.Stimulus) registerControllers()
})
