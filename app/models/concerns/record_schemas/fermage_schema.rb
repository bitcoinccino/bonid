# frozen_string_literal: true

# BonID — Fermage Schema (DGI-55)
# =====================================================
# Official DGI form for land lease tax (Fèmaj).
# Tax components: droit annuel, surtaxe, DTP, solidarité.
# =====================================================

module RecordSchemas
  module FermageSchema
    extend ActiveSupport::Concern

    included do
      validate :validate_fermage_schema, if: -> { record_type == "fermage" && status != "draft" }
    end

    # ================================================================
    # Validation
    # ================================================================
    def validate_fermage_schema
      return unless data.is_a?(Hash)

      fermier   = data["fermier"] || {}
      propriete = data["propriete"] || {}
      calcul    = data["calcul_fermage"] || {}

      # Fermier
      missing = []
      missing << "nom"         unless fermier["nom"].present?
      missing << "demeurant_a" unless fermier["demeurant_a"].present?
      errors.add(:data, I18n.t("alerts.dgi_form.missing_fields_in", fields: missing.join(", "), section: I18n.t("alerts.dgi_form.sections.tenant"))) if missing.any?

      # Propriete
      prop_missing = []
      prop_missing << "habitation_ou_rue" unless propriete["habitation_ou_rue"].present?
      prop_missing << "section"           unless propriete["section"].present?
      prop_missing << "commune"           unless propriete["commune"].present?
      prop_missing << "departement"       unless propriete["departement"].present?
      prop_missing << "exercice"          unless propriete["exercice"].present?
      errors.add(:data, I18n.t("alerts.dgi_form.missing_fields_in", fields: prop_missing.join(", "), section: I18n.t("alerts.dgi_form.sections.property"))) if prop_missing.any?

      if propriete["departement"].present?
        unless RecordSchemas::NifRegistrationSchema::DEPARTEMENTS_HAITI.include?(propriete["departement"])
          errors.add(:data, I18n.t("alerts.dgi_form.department_invalid"))
        end
      end

      if propriete["exercice"].present? && !propriete["exercice"].match?(/\A\d{4}-\d{4}\z/)
        errors.add(:data, I18n.t("alerts.dgi_form.fiscal_year_format"))
      end

      # Calcul
      errors.add(:data, I18n.t("alerts.dgi_form.annual_fee_required")) if calcul["droit_annuel"].blank?

      %w[droit_annuel surtaxe dtp solidarite total].each do |field|
        val = calcul[field]
        next if val.blank?
        errors.add(:data, I18n.t("alerts.dgi_form.number_invalid", field: field)) unless val.to_s.match?(/\A-?\d+(\.\d+)?\z/)
      end

      if calcul["droit_annuel"].present? && calcul["droit_annuel"].to_f < 0
        errors.add(:data, I18n.t("alerts.dgi_form.annual_fee_negative"))
      end
    end

    # ================================================================
    # Accessors
    # ================================================================

    # Fermier
    def fermage_nom             = data.dig("fermier", "nom")
    def fermage_demeurant_a     = data.dig("fermier", "demeurant_a")
    def fermage_telephone       = data.dig("fermier", "telephone")
    def fermage_email           = data.dig("fermier", "email")
    def fermage_nif             = data.dig("fermier", "nif")
    def fermage_cin             = data.dig("fermier", "cin")

    # Propriete
    def fermage_habitation      = data.dig("propriete", "habitation_ou_rue")
    def fermage_section         = data.dig("propriete", "section")
    def fermage_commune         = data.dig("propriete", "commune")
    def fermage_departement     = data.dig("propriete", "departement")
    def fermage_superficie      = data.dig("propriete", "superficie")
    def fermage_no_cadastre     = data.dig("propriete", "no_cadastre")
    def fermage_exercice        = data.dig("propriete", "exercice")

    # Calcul
    def fermage_droit_annuel    = data.dig("calcul_fermage", "droit_annuel").to_f
    def fermage_surtaxe         = data.dig("calcul_fermage", "surtaxe").to_f
    def fermage_dtp             = data.dig("calcul_fermage", "dtp").to_f
    def fermage_solidarite      = data.dig("calcul_fermage", "solidarite").to_f
    def fermage_total           = data.dig("calcul_fermage", "total").to_f

    # Signature
    def fermage_declarant_nom   = data.dig("signature", "nom_prenom")
    def fermage_date_presentation = data.dig("signature", "date_presentation")

    # Display
    def fermage_summary
      "Fèmaj #{fermage_exercice} - #{fermage_commune} - #{fermage_total.round(2)} HTG"
    end
  end
end
