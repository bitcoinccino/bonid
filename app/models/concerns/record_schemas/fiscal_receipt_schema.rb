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
    # Covers all services and taxes a citizen might pay at DGI
    VALID_TAX_TYPES = %w[
      timbre_passeport
      timbre_visa
      timbre_acte_naissance
      timbre_mariage
      timbre_notaire
      timbre_judiciaire
      contribution_fonciere
      patente
      impot_revenu
      impot_locatif
      acompte_provisionnel
      cfgdct
      caisse_assistance_sociale
      droit_licence_etranger
      droit_fonctionnement
      droit_non_fonctionnement
      droit_douane
      droit_enregistrement
      droit_succession
      droit_mutation
      legalisation_pieces
      carte_identite_professionnelle
      certificat_decharge_fiscale
      quitus_fiscal
      taxe_transfer_propriete
      taxe_vehicule
      taxe_telecommunication
      taxe_assurance
      penalite_retard
      amende_fiscale
      other
    ].freeze

    # Human-readable labels for display (Haitian Creole)
    TAX_TYPE_LABELS = {
      "timbre_passeport"              => "Tènb Paspò",
      "timbre_visa"                   => "Tènb Viza",
      "timbre_acte_naissance"         => "Tènb Ak Nesans",
      "timbre_mariage"                => "Tènb Maryaj",
      "timbre_notaire"                => "Tènb Notè",
      "timbre_judiciaire"             => "Tènb Jidisyè",
      "contribution_fonciere"         => "Kontribisyon Fonsyè",
      "patente"                       => "Patant",
      "impot_revenu"                  => "Enpò sou Revni",
      "impot_locatif"                 => "Enpò Lokatif",
      "acompte_provisionnel"          => "Akont Pwovizyon",
      "cfgdct"                        => "CFGDCT",
      "caisse_assistance_sociale"     => "Kès Asistans Sosyal",
      "droit_licence_etranger"        => "Dwa Lisans Etranje",
      "droit_fonctionnement"          => "Dwa Fonksyonman",
      "droit_non_fonctionnement"      => "Dwa Non-Fonksyonman",
      "droit_douane"                  => "Dwa Ladwàn",
      "droit_enregistrement"          => "Dwa Anrejistreman",
      "droit_succession"              => "Dwa Siksesyon",
      "droit_mutation"                => "Dwa Mitasyon",
      "legalisation_pieces"           => "Legalizasyon Pyès",
      "carte_identite_professionnelle" => "Kat Idantite Pwofesyonèl",
      "certificat_decharge_fiscale"   => "Sètifika Dechaj Fiskal",
      "quitus_fiscal"                 => "Kitis Fiskal",
      "taxe_transfer_propriete"       => "Taks Transfè Pwopriyete",
      "taxe_vehicule"                 => "Taks Veyikil",
      "taxe_telecommunication"        => "Taks Telekominikasyon",
      "taxe_assurance"                => "Taks Asirans",
      "penalite_retard"               => "Penalite Reta",
      "amende_fiscale"                => "Amand Fiskal",
      "other"                         => "Lòt"
    }.freeze

    VALID_PAYMENT_METHODS = %w[cash check transfer mobile_money natcash moncash].freeze

    PAYMENT_METHOD_LABELS = {
      "cash"         => "Kach",
      "check"        => "Chèk",
      "transfer"     => "Transfè Bankè",
      "mobile_money" => "Lajan Mobil",
      "natcash"      => "NatCash",
      "moncash"      => "MonCash"
    }.freeze

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
    def tax_type_label
      TAX_TYPE_LABELS[tax_type] || tax_type&.titleize || "—"
    end

    def payment_method_label
      PAYMENT_METHOD_LABELS[payment_method] || payment_method&.titleize || "—"
    end

    def receipt_summary
      "#{tax_type_label} — #{amount_htg&.to_i} HTG — #{payment_date}"
    end

    def consumption_summary
      return "Disponib" unless consumed?

      "Konsome pa #{consumed_by_agency} le #{consumed_at} (Ofisye: #{consumed_by_officer_id})"
    end

    # Class-level helpers for forms
    def self.tax_type_options
      TAX_TYPE_LABELS.map { |key, label| [ label, key ] }
    end

    def self.payment_method_options
      PAYMENT_METHOD_LABELS.map { |key, label| [ label, key ] }
    end
  end
end
