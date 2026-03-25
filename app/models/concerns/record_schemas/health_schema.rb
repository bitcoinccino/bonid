# frozen_string_literal: true

# 🇭🇹 BonID Health Schema
# Defines the structure and validation rules for health insurance
# and medical profile records within BonID’s verification system.
#
# This concern is included in VerificationRecord or other models
# handling JSON-based health record data.
#
# Each key represents an expected JSON attribute type and format.
# ============================================================================
module RecordSchemas
  module HealthSchema
    extend ActiveSupport::Concern

    included do
      validate :validate_health_schema, if: -> { record_type == "health" }
    end

    # === SCHEMA DEFINITION ===================================================
    HEALTH = {
      # === PATIENT INFO ===
      "patient_name"           => "string",
      "patient_national_id"    => "string",
      "patient_dob"            => "date",
      "patient_gender"         => "string",
      "ordering_provider"      => "string",

      # === INSURANCE INFO ===
      "provider_name"          => "string",
      "policy_number"          => "string",
      "coverage_type"          => "string",
      "valid_from"             => "date",
      "valid_until"            => "date",
      "renewal_date"           => "date",
      "premium_amount_htg"     => "integer",
      "payment_frequency"      => "string",
      "coverage_limit_htg"     => "integer",
      "deductible_htg"         => "integer",
      "coinsurance_rate"       => "string",
      "exclusions"             => "array",

      # === BENEFICIARIES & MEMBERS ===
      "insured_name"           => "string",
      "policy_holder_id"       => "string",
      "beneficiaries"          => "array",

      # === HEALTH PROFILE ===
      "blood_type"             => "string",
      "vaccinations"           => "array",
      "allergies"              => "array",
      "chronic_conditions"     => "array",
      "current_medications"    => "array",
      "doctor_name"            => "string",
      "hospital_affiliation"   => "string",
      "preferred_pharmacy"     => "string",
      "last_checkup_date"      => "date",
      "next_checkup_date"      => "date",

      # === LAB RESULTS ===
      "lab_reports"            => "array", # [{ type:, test_date:, collected_at:, results:, overall_assessment:, notes:, lab_technician:, lab_id: }]

      # === VERIFICATION ===
      "verified_by"            => "object", # { institution:, verifying_physician:, verification_date:, license_number:, compliance_standard:, signature_file: }

      # === DOCUMENTS & REFERENCES ===
      "documents"              => "array",  # [{ type:, file_id: }]
      "linked_cnss_number"     => "string",

      # === EMERGENCY CONTACT ===
      "emergency_contact"      => "object"  # { name:, relationship:, phone: }
    }.freeze

    # === VALIDATION ==========================================================
    REQUIRED_FIELDS = %w[
      patient_name
      patient_national_id
      blood_type
    ].freeze

    def validate_health_schema
      missing = REQUIRED_FIELDS - (data.keys rescue [])
      errors.add(:data, "Missing required health fields: #{missing.join(', ')}") if missing.any?
    end
  end
end
