# frozen_string_literal: true

# 🇭🇹 BonID — Fiscal Receipt Schema
# ====================================
# Defines structure and validation rules for DGI fiscal receipt records.
# These represent tax payments (timbres fiscaux, patente, impôt sur le revenu, etc.)
# issued by the Direction Générale des Impôts (DGI) and verifiable by downstream
# agencies such as Immigration for passport issuance.
#
# JSON layout:
# {
#   "receipt":     { receipt_number, tax_type, amount_htg, ... },
#   "payer":       { name, nif, bonid },
#   "consumption": { consumed, consumed_at, consumed_by_agency, ... },
#   "documents":   []
# }
#
# Key feature: one-time consumption — once a receipt is consumed by an agency
# (e.g., Immigration marks it as used for a passport), it cannot be reused.
# This directly prevents the fake-stamp fraud documented in Haiti's passport system.
# ====================================

module RecordSchemas
  module FiscalReceiptSchema
    extend ActiveSupport::Concern

    included do
      validate :validate_fiscal_receipt_schema, if: -> { record_type == "fiscal_receipt" }
    end

    # === DGI Tax Types (from dgi.gouv.ht/textes-de-loi) ===
    VALID_TAX_TYPES = %w[
      timbre_passeport
      contribution_fonciere
      patente
      impot_revenu
      acompte_provisionnel
      cfgdct
      caisse_assistance_sociale
      droit_licence_etranger
      droit_fonctionnement
      droit_non_fonctionnement
      legalisation_pieces
      carte_identite_professionnelle
      other
    ].freeze

    VALID_PAYMENT_METHODS = %w[cash check transfer mobile_money].freeze

    # === Required Fields ===
    FISCAL_RECEIPT_REQUIRED_FIELDS = %w[
      receipt_number
      tax_type
      amount_htg
      payment_date
      dgi_office_code
      fiscal_year
    ].freeze

    # === Core Validation ===
    def validate_fiscal_receipt_schema
      return unless data.is_a?(Hash)

      receipt = data["receipt"] || {}
      payer   = data["payer"]   || {}

      # --- Required field presence ---
      missing = []
      missing << "receipt_number"  unless receipt["receipt_number"].present?
      missing << "tax_type"        unless receipt["tax_type"].present?
      missing << "amount_htg"      unless receipt["amount_htg"].present?
      missing << "payment_date"    unless receipt["payment_date"].present?
      missing << "dgi_office_code" unless receipt["dgi_office_code"].present?
      missing << "fiscal_year"     unless receipt["fiscal_year"].present?

      if missing.any?
        errors.add(:data, "is missing required fiscal receipt fields: #{missing.join(', ')}")
      end

      # --- Tax type validation ---
      if receipt["tax_type"].present? && !VALID_TAX_TYPES.include?(receipt["tax_type"])
        errors.add(:data, "tax_type must be one of: #{VALID_TAX_TYPES.join(', ')}")
      end

      # --- Amount must be positive ---
      if receipt["amount_htg"].present? && receipt["amount_htg"].to_i <= 0
        errors.add(:data, "amount_htg must be a positive number")
      end

      # --- Payment method validation ---
      if receipt["payment_method"].present? && !VALID_PAYMENT_METHODS.include?(receipt["payment_method"])
        errors.add(:data, "payment_method must be one of: #{VALID_PAYMENT_METHODS.join(', ')}")
      end

      # --- NIF format validation (if provided) ---
      if payer["nif"].present? && !payer["nif"].match?(/\ANIF-HT-\d{9}\z/)
        errors.add(:data, "payer nif must follow format NIF-HT-XXXXXXXXX")
      end

      # --- Fiscal year format (e.g., "2025-2026") ---
      if receipt["fiscal_year"].present? && !receipt["fiscal_year"].match?(/\A\d{4}-\d{4}\z/)
        errors.add(:data, "fiscal_year must follow format YYYY-YYYY (e.g., 2025-2026)")
      end

      # --- Payment date must be parseable ---
      if receipt["payment_date"].present?
        begin
          Date.parse(receipt["payment_date"])
        rescue ArgumentError
          errors.add(:data, "payment_date must be a valid date")
        end
      end
    end

    # ================================================================
    # Receipt Consumption (One-Time Use)
    # ================================================================
    # Called by Immigration (or any consuming agency) to mark a receipt
    # as used. Once consumed, the receipt cannot be reused — this is the
    # core mechanism that prevents the fake-stamp fraud.
    #
    # Usage:
    #   record.consume!(agency: "immigration", officer_id: "IMM-OFF-2291")
    #
    # Returns true on success, raises ActiveRecord::RecordInvalid on failure.
    # ================================================================
    def consume!(agency:, officer_id:, metadata: {})
      consumption = data["consumption"] || {}

      if consumption["consumed"] == true
        errors.add(:base,
          "Receipt #{receipt_number} was already consumed on " \
          "#{consumption['consumed_at']} by #{consumption['consumed_by_agency']} " \
          "(officer: #{consumption['consumed_by_officer_id']})")
        raise ActiveRecord::RecordInvalid, self
      end

      data["consumption"] = {
        "consumed"               => true,
        "consumed_at"            => Time.current.iso8601,
        "consumed_by_agency"     => agency.to_s,
        "consumed_by_officer_id" => officer_id.to_s,
        "metadata"               => metadata
      }

      save!
    end

    def consumed?
      data.dig("consumption", "consumed") == true
    end

    def consumable?
      status == "verified" && !consumed?
    end

    # ================================================================
    # Accessors (Safe Navigation into Nested JSON)
    # ================================================================

    # --- Receipt ---
    def receipt_number   = data.dig("receipt", "receipt_number")
    def tax_type         = data.dig("receipt", "tax_type")
    def amount_htg       = data.dig("receipt", "amount_htg")&.to_i
    def payment_date     = data.dig("receipt", "payment_date")
    def dgi_office_code  = data.dig("receipt", "dgi_office_code")
    def fiscal_year      = data.dig("receipt", "fiscal_year")
    def payment_method   = data.dig("receipt", "payment_method")
    def cashier_id       = data.dig("receipt", "cashier_id")
    def batch_number     = data.dig("receipt", "batch_number")

    # --- Payer ---
    def payer_name       = data.dig("payer", "name")
    def payer_nif        = data.dig("payer", "nif")
    def payer_bonid      = data.dig("payer", "bonid")

    # --- Consumption ---
    def consumed_at            = data.dig("consumption", "consumed_at")
    def consumed_by_agency     = data.dig("consumption", "consumed_by_agency")
    def consumed_by_officer_id = data.dig("consumption", "consumed_by_officer_id")

    # --- Documents ---
    def receipt_documents = data["documents"] || []

    # === Display Helpers ===
    def receipt_summary
      "#{tax_type&.titleize} — #{amount_htg&.to_i} HTG — #{payment_date}"
    end

    def consumption_summary
      return "Available" unless consumed?

      "Consumed by #{consumed_by_agency} on #{consumed_at} (Officer: #{consumed_by_officer_id})"
    end
  end
end
