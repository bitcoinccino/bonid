# frozen_string_literal: true

# 🇭🇹 BonID Property Schema
# Defines the base structure and validation rules for Property records.
# These represent verified parcels, buildings, or land units in Haiti’s cadastral system.
# frozen_string_literal: true

# 🇭🇹 BonID — Property Schema (Nested JSON)
# =========================================
# Defines structure and validation rules for property (land / building) records.
# Uses a nested JSON layout to support modular growth and clean partner APIs:
#
# {
#   "property": { ... },
#   "valuation": { ... },
#   "buyer": { ... },
#   "seller": { ... }
# }
#
# This structure avoids key collisions and supports scalable, namespaced validation.
# ================================================================

module RecordSchemas
  module PropertySchema
    extend ActiveSupport::Concern

    included do
      validate :validate_property_schema,
               if: -> { record_type == "property" && (category.blank? || category == "land_transaction") }
    end

    # === Nested Required Fields ===
    PROPERTY_REQUIRED_FIELDS = %w[
      title_number
      cadastral_ref
      commune
      section_communal
      location
      property_type
      area_m2
      owner_since
      valuation.market_value_htg
    ].freeze

    # === Main Validator ===
    def validate_property_schema
      return unless data.is_a?(Hash)

      property  = data["property"]  || {}
      valuation = data["valuation"] || {}

      missing = []
      missing << "title_number" unless property["title_number"].present?
      missing << "commune" unless property["commune"].present?
      missing << "area_m2" unless property["area_m2"].present?

      if missing.any?
        errors.add(:data, "is missing required property fields: #{missing.join(', ')}")
      end

      if property["area_m2"].present? && property["area_m2"].to_f <= 0
        errors.add(:data, "area_m2 must be a positive number")
      end
    end

    # === Accessors (Safe Navigation) ===
    def title_number         = data.dig("property", "title_number")
    def cadastral_ref        = data.dig("property", "cadastral_ref")
    def commune              = data.dig("property", "commune")
    def section_communal     = data.dig("property", "section_communal")
    def address              = data.dig("property", "location")
    def property_type        = data.dig("property", "property_type")
    def area_m2              = data.dig("property", "area_m2")&.to_f
    def owner_since          = data.dig("property", "owner_since")
    def valuation_htg        = data.dig("valuation", "market_value_htg")&.to_i
    def last_appraisal_date  = data.dig("valuation", "last_appraisal_date")
    def zoning_use           = data.dig("property", "zoning_use")
    def coordinates          = data["coordinates"] || {}
    def coowners             = data["coowners"] || []
    def permit               = data["permit"] || {}
    def legal                = data["legal"] || {}
    def documents            = data["documents"] || []

    # === Display Helper ===
    def full_address
      [
        data.dig("property", "location"),
        data.dig("property", "section_communal"),
        data.dig("property", "commune"),
        "Haiti"
      ].compact.join(", ")
    end
  end
end
