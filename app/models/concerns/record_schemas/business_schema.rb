# app/models/concerns/record_schemas/business_schema.rb
module RecordSchemas
  module BusinessSchema
    extend ActiveSupport::Concern

    included do
      validate :business_schema, if: -> { record_type == "business" }
    end

    # === Haiti-specific required fields ===
    BUSINESS_REQUIRED_FIELDS = %w[
      business_name
      registration_number
      business_type
      legal_structure
      nif
      business_address
      sector
      cnss_employer_number
      incorporation_date
    ].freeze

    # === Core validation ===
    def business_schema
      required = BUSINESS_REQUIRED_FIELDS
      missing = required.select { |field| data[field.to_s].blank? }

      # Check for owner role (mandatory in Haiti)
      if data["owner_role"].blank?
        missing << "owner_role"
      end

      if missing.any?
        errors.add(:data, "missing required business fields: #{missing.join(', ')}")
      end

      # === Field-level format validation ===
      if data["nif"] && !data["nif"].match?(/\ANIF-HT-\d{9}\z/)
        errors.add(:data, "nif must follow format NIF-HT-XXXXXXXXX")
      end

      if data["cnss_employer_number"] && !data["cnss_employer_number"].match?(/\ACNSS-BIZ-\d{4}-\d{3}\z/)
        errors.add(:data, "cnss_employer_number must follow format CNSS-BIZ-YYYY-NNN")
      end

      # === Numeric & date logic ===
      if data["annual_revenue_htg"] && data["annual_revenue_htg"].to_i < 0
        errors.add(:data, "annual_revenue_htg must be non-negative")
      end

      if data["employees_count"] && data["employees_count"].to_i < 0
        errors.add(:data, "employees_count must be non-negative")
      end

      if data["incorporation_date"] && data["license_expiration"]
        inc_date = Date.parse(data["incorporation_date"]) rescue nil
        exp_date = Date.parse(data["license_expiration"]) rescue nil
        if inc_date && exp_date && exp_date <= inc_date
          errors.add(:data, "license_expiration must be after incorporation_date")
        end
      end

      # === CNSS registration rule ===
      if data["incorporation_date"] && data["cnss_registration_date"]
        inc_date = Date.parse(data["incorporation_date"]) rescue nil
        cnss_date = Date.parse(data["cnss_registration_date"]) rescue nil
        if inc_date && cnss_date && (cnss_date - inc_date).to_i > 15
          errors.add(:data, "cnss_registration_date must be within 15 days of incorporation_date")
        end
      end
    end

    # === Helper accessors (for APIs/UI) ===
    def business_name        = data["business_name"]
    def registration_number   = data["registration_number"]
    def legal_structure       = data["legal_structure"]
    def business_address      = data["business_address"]
    def sector                = data["sector"]
    def incorporation_date    = data["incorporation_date"]
    def owner_role            = data["owner_role"]
  end
end
