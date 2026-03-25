# frozen_string_literal: true

# 🇭🇹 BonID Land Transaction Schema
# Defines the structure for property-based land transactions such as sales,
# donations, inheritances, or genuine deeds.
module RecordSchemas
  module LandTransactionSchema
    extend ActiveSupport::Concern

    included do
      validate :validate_land_transaction_schema, if: -> { record_type == "property" && category == "land_transaction" }
    end

    LAND_TRANSACTION_REQUIRED_FIELDS = %w[
      transaction_id
      transaction_type
      date_initiated
      status
      property
      buyer
      seller
    ].freeze

    def validate_land_transaction_schema
      return unless data.is_a?(Hash)

      missing = LAND_TRANSACTION_REQUIRED_FIELDS.reject { |f| data[f].present? }
      errors.add(:data, "is missing required land transaction fields: #{missing.join(', ')}") if missing.any?

      # Cross-validation: ensure base property info exists
      unless data["property"].is_a?(Hash) && data["property"]["location"].present?
        errors.add(:data, "must include a valid property reference (location required)")
      end

      # Validate cost structure
      if data["total_cost_htg"].to_i < 0
        errors.add(:data, "total_cost_htg cannot be negative")
      end
    end

    # === Accessor Helpers ===
    def transaction_id            = data["transaction_id"]
    def transaction_type          = data["transaction_type"]
    def transaction_status        = data["status"]
    def transaction_date          = data["date_initiated"]
    def estimated_completion      = data["estimated_completion"]

    # Cost breakdown
    def total_cost_htg            = data["total_cost_htg"].to_i
    def notary_fees_percent       = data.dig("cost_breakdown", "notary_fees_percent").to_f
    def survey_fees_htg           = data.dig("cost_breakdown", "survey_fees_htg").to_i
    def taxes_htg                 = data.dig("cost_breakdown", "taxes_htg").to_i
    def transfer_fees_htg         = data.dig("cost_breakdown", "transfer_fees_htg").to_i

    # Buyer & Seller accessors
    def buyer_info                = data["buyer"] || {}
    def seller_info               = data["seller"] || {}
    def property_info             = data["property"] || {}
    def steps_info                = data["steps"] || {}
    def documents                 = data["documents"] || []

    # Computed readable summaries
    def buyer_name                = buyer_info["name"]
    def seller_name               = seller_info["name"]
    def buyer_type                = buyer_info["type"]
    def seller_type               = seller_info["type"]
    def property_location         = property_info["location"]
    def survey_date               = steps_info.dig("step_2_survey", "survey_date")

    # Derived financial total (sum of components)
    def total_estimated_cost_htg
      total_cost_htg + survey_fees_htg + taxes_htg + transfer_fees_htg
    end
  end
end
