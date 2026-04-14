# frozen_string_literal: true

# BonID — TCA Declaration Schema (Taxe sur le Chiffre d'Affaires)
# ================================================================
# Monthly sales tax. Businesses collect TCA (10%) from customers,
# deduct TCA paid on purchases (input credit), remit difference to DGI.
# ================================================================

module RecordSchemas
  module TcaDeclarationSchema
    extend ActiveSupport::Concern

    included do
      validate :validate_tca_declaration_schema, if: -> { record_type == "tca_declaration" && status != "draft" }
    end

    TAUX_TCA = 10.0 / 100  # 10%

    # ================================================================
    # Validation
    # ================================================================
    def validate_tca_declaration_schema
      return unless data.is_a?(Hash)

      periode = data["periode"] || {}
      ident   = data["identification"] || {}
      calcul  = data["calcul_tca"] || {}

      # Periode
      errors.add(:data, "Ane fiskal obligatwa") if periode["annee_fiscale"].blank?
      if periode["annee_fiscale"].present? && !periode["annee_fiscale"].match?(/\A\d{4}-\d{4}\z/)
        errors.add(:data, "Ane fiskal dwe nan foma YYYY-YYYY")
      end
      errors.add(:data, "Mwa deklarasyon obligatwa") if periode["mois_declaration"].blank?
      if periode["mois_declaration"].present? && !(1..12).include?(periode["mois_declaration"].to_i)
        errors.add(:data, "Mwa deklarasyon dwe ant 1 ak 12")
      end

      if periode["type_declaration"].present?
        unless %w[originale rectificative].include?(periode["type_declaration"])
          errors.add(:data, "Tip deklarasyon dwe 'originale' oswa 'rectificative'")
        end
      else
        errors.add(:data, "Tip deklarasyon obligatwa")
      end

      # Identification
      missing = []
      missing << "raison_sociale" unless ident["raison_sociale"].present?
      missing << "nif"            unless ident["nif"].present?
      missing << "adresse"        unless ident["adresse"].present?
      missing << "ville"          unless ident["ville"].present?
      errors.add(:data, "Chan obligatwa ki manke: #{missing.join(', ')}") if missing.any?

      if ident["nif"].present? && !ident["nif"].match?(/\A(\d{3}-\d{3}-\d{3}|NIF-HT-\d{9})\z/)
        errors.add(:data, "NIF dwe nan foma XXX-XXX-XXX oswa NIF-HT-XXXXXXXXX")
      end

      # Calcul — chiffre_affaires_brut required
      errors.add(:data, "Chif afe brit obligatwa") if calcul["chiffre_affaires_brut"].blank?

      %w[chiffre_affaires_brut ventes_exonerees ventes_exportation achats_locaux_tca achats_importation_tca tca_retenu_source interets_retard amende].each do |field|
        val = calcul[field]
        next if val.blank?
        errors.add(:data, "#{field} dwe yon nimewo valid") unless val.to_s.match?(/\A-?\d+(\.\d+)?\z/)
      end
    end

    # ================================================================
    # TCA Calculation Engine
    # ================================================================
    def calculate_tca(chiffre_affaires_brut:, ventes_exonerees: 0, ventes_exportation: 0, achats_locaux_tca: 0, achats_importation_tca: 0, tca_retenu_source: 0, interets_retard: 0, amende: 0)
      brut   = chiffre_affaires_brut.to_f
      exo    = ventes_exonerees.to_f
      export = ventes_exportation.to_f
      al_tca = achats_locaux_tca.to_f
      ai_tca = achats_importation_tca.to_f
      trs    = tca_retenu_source.to_f
      ir     = interets_retard.to_f
      am     = amende.to_f

      taxable       = [brut - exo - export, 0].max
      tca_collectee = (taxable * TAUX_TCA).round(2)
      total_credit  = al_tca + ai_tca + trs
      tca_nette     = (tca_collectee - total_credit).round(2)

      credit_reportable = tca_nette < 0 ? tca_nette.abs : 0
      tca_due           = [tca_nette, 0].max
      total             = tca_due + ir + am

      {
        "chiffre_affaires_brut"     => brut.round(2),
        "ventes_exonerees"          => exo.round(2),
        "ventes_exportation"        => export.round(2),
        "chiffre_affaires_taxable"  => taxable.round(2),
        "tca_collectee"             => tca_collectee,
        "achats_locaux_tca"         => al_tca.round(2),
        "achats_importation_tca"    => ai_tca.round(2),
        "tca_retenu_source"         => trs.round(2),
        "total_credit_tca"          => total_credit.round(2),
        "tca_nette"                 => tca_nette,
        "credit_reportable"         => credit_reportable.round(2),
        "tca_due"                   => tca_due.round(2),
        "interets_retard"           => ir.round(2),
        "amende"                    => am.round(2),
        "total"                     => total.round(2)
      }
    end

    # ================================================================
    # Accessors
    # ================================================================

    # Declaration Number
    def tca_declaration_number = data["declaration_number"]

    # Periode
    def tca_annee_fiscale     = data.dig("periode", "annee_fiscale")
    def tca_mois_declaration  = data.dig("periode", "mois_declaration")&.to_i
    def tca_type_declaration  = data.dig("periode", "type_declaration")

    # Identification
    def tca_raison_sociale    = data.dig("identification", "raison_sociale")
    def tca_nif               = data.dig("identification", "nif")
    def tca_adresse           = data.dig("identification", "adresse")
    def tca_ville             = data.dig("identification", "ville")
    def tca_telephone         = data.dig("identification", "telephone")
    def tca_email             = data.dig("identification", "email")
    def tca_numero_patente    = data.dig("identification", "numero_patente")

    # Calcul
    def tca_ca_brut           = data.dig("calcul_tca", "chiffre_affaires_brut").to_f
    def tca_ventes_exo        = data.dig("calcul_tca", "ventes_exonerees").to_f
    def tca_ventes_export     = data.dig("calcul_tca", "ventes_exportation").to_f
    def tca_ca_taxable        = data.dig("calcul_tca", "chiffre_affaires_taxable").to_f
    def tca_collectee         = data.dig("calcul_tca", "tca_collectee").to_f
    def tca_achats_locaux     = data.dig("calcul_tca", "achats_locaux_tca").to_f
    def tca_achats_import     = data.dig("calcul_tca", "achats_importation_tca").to_f
    def tca_retenu_source     = data.dig("calcul_tca", "tca_retenu_source").to_f
    def tca_total_credit      = data.dig("calcul_tca", "total_credit_tca").to_f
    def tca_nette_amount      = data.dig("calcul_tca", "tca_nette").to_f
    def tca_credit_reportable = data.dig("calcul_tca", "credit_reportable").to_f
    def tca_due               = data.dig("calcul_tca", "tca_due").to_f
    def tca_interets_retard   = data.dig("calcul_tca", "interets_retard").to_f
    def tca_amende            = data.dig("calcul_tca", "amende").to_f
    def tca_total             = data.dig("calcul_tca", "total").to_f

    # Paiement
    def tca_methode_paiement  = data.dig("paiement", "methode")
    def tca_numero_cheque     = data.dig("paiement", "numero_cheque")
    def tca_banque            = data.dig("paiement", "banque")

    # Signature
    def tca_declarant_nom      = data.dig("signature", "nom_prenom")
    def tca_declarant_nif      = data.dig("signature", "nif_declarant")
    def tca_date_presentation  = data.dig("signature", "date_presentation")

    # Display
    def tca_summary
      "TCA #{tca_annee_fiscale}/#{tca_mois_declaration} - #{tca_raison_sociale} - #{tca_total.round(2)} HTG"
    end

    CALCUL_TCA_LINES = {
      1  => { key: "chiffre_affaires_brut",    label: "Chif Afe Brit",                    editable: true },
      2  => { key: "ventes_exonerees",         label: "Vant Egzonere",                    editable: true },
      3  => { key: "ventes_exportation",       label: "Vant Ekspo (0% TCA)",              editable: true },
      4  => { key: "chiffre_affaires_taxable", label: "Chif Afe Taksab (Liy 1-2-3)",     editable: false },
      5  => { key: "tca_collectee",            label: "TCA Kolekte (Liy 4 x 10%)",        editable: false, rate: "10%" },
      6  => { key: "achats_locaux_tca",        label: "TCA peye sou Acha Lokal",          editable: true },
      7  => { key: "achats_importation_tca",   label: "TCA peye sou Enpotasyon",          editable: true },
      8  => { key: "tca_retenu_source",        label: "TCA Retni nan Sous",               editable: true },
      9  => { key: "total_credit_tca",         label: "Total Kredi TCA (Liy 6+7+8)",      editable: false },
      10 => { key: "tca_nette",                label: "TCA Net (Liy 5 - Liy 9)",          editable: false },
      11 => { key: "credit_reportable",        label: "Kredi Repotab (si negatif)",        editable: false },
      12 => { key: "tca_due",                  label: "TCA pou Peye",                      editable: false },
      13 => { key: "interets_retard",          label: "Entere Reta",                       editable: true },
      14 => { key: "amende",                   label: "Amand",                             editable: true },
      15 => { key: "total",                    label: "TOTAL",                             editable: false }
    }.freeze
  end
end
