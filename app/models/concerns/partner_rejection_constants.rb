module PartnerRejectionConstants
  extend ActiveSupport::Concern

  REJECTION_REASONS = {
    incomplete_application:      "Incomplete application",
    invalid_business_info:       "Invalid or unverifiable business information",
    invalid_address:             "Invalid or unverifiable address",
    unverified_contact:          "Unable to verify point of contact",
    missing_documents:           "Missing required documents",
    fraud_suspected:             "Suspicious or fraudulent activity detected",
    business_not_found:          "Company does not exist in Haiti business registry",
    sector_not_allowed:          "Sector not approved for BonID at this time",
    invalid_email_domain:        "Email domain not associated with claimed organization",
    impersonation:               "Impersonating another company or government institution",
    security_concerns:           "Security or compliance concerns",
    high_risk:                   "High-risk activity outside BonID policy",
    misuse_form:                 "Misuse of BonID onboarding form",
    duplicate_application:       "Duplicate or conflicting application",
    application_withdrawn:       "Application withdrawn",
    other:                       "Other"
  }.freeze

  class_methods do
    def rejection_reason_options
      REJECTION_REASONS.map { |key, label| [ label, key.to_s ] }
    end
  end
end
