# frozen_string_literal: true

# BonID — Patente Declaration Schema (DGI-F008)
# =====================================================
# Official DGI form for Patente (annual business license tax).
# Cashier enters 3 values + adjustments, system auto-calculates 15 lines.
# =====================================================

module RecordSchemas
  module PatenteDeclarationSchema
    extend ActiveSupport::Concern

    included do
      validate :validate_patente_declaration_schema, if: -> { record_type == "patente_declaration" && status != "draft" }
    end

    DECLARATION_TYPES = %w[originale rectificative].freeze

    SECTEUR_ACTIVITE = {
      "A" => "Agrikilti, Elvaj, Lapes",
      "B" => "Endistri Ekstraksyon (Min, Karye)",
      "C" => "Endistri Manifakti",
      "D" => "Distribisyon Elektrisite, Gaz, Dlo",
      "E" => "Jesyon Dlo ak Deche",
      "F" => "Konstriksyon",
      "G" => "Komes (Angwo ak Detay)",
      "H" => "Transpo ak Antrepozaj",
      "I" => "Otel, Restoran, Touris",
      "J" => "Enfomasyon ak Kominikasyon",
      "K" => "Aktivite Finansye ak Asirans",
      "L" => "Aktivite Imobilye",
      "M" => "Aktivite Pwofesyonel, Syantifik, Teknik",
      "N" => "Sevis Administratif ak Sipo",
      "O" => "Administrasyon Piblik",
      "P" => "Edikasyon",
      "Q" => "Sante ak Aksyon Sosyal",
      "R" => "Atizay, Espektik, Lwazi",
      "S" => "Lot Aktivite Sevis",
      "T" => "Aktivite Domestik",
      "U" => "Oganizasyon Entenasyonal"
    }.freeze

    TAUX_PARTIE_VARIABLE = 4.0 / 1000   # 4/1000
    TAUX_DSAV            = 2.0 / 1000   # 2/1000

    # ================================================================
    # Validation
    # ================================================================
    def validate_patente_declaration_schema
      return unless data.is_a?(Hash)

      periode = data["periode"] || {}
      ident   = data["identification"] || {}
      calcul  = data["calcul_taxe"] || {}

      # Section I
      errors.add(:data, "Ane fiskal obligatwa (Section I)") if periode["annee_fiscale"].blank?

      if periode["annee_fiscale"].present? && !periode["annee_fiscale"].match?(/\A\d{4}-\d{4}\z/)
        errors.add(:data, "Ane fiskal dwe nan foma YYYY-YYYY")
      end

      if periode["mois_depot"].present? && !(1..12).include?(periode["mois_depot"].to_i)
        errors.add(:data, "Mwa depo dwe ant 1 ak 12")
      end

      # Section II
      if periode["type_declaration"].present?
        unless DECLARATION_TYPES.include?(periode["type_declaration"])
          errors.add(:data, "Tip deklarasyon dwe 'originale' oswa 'rectificative'")
        end
      else
        errors.add(:data, "Tip deklarasyon obligatwa (Section II)")
      end

      # Section III
      missing = []
      missing << "raison_sociale" unless ident["raison_sociale"].present?
      missing << "nif"            unless ident["nif"].present?
      missing << "adresse"        unless ident["adresse"].present?
      missing << "ville"          unless ident["ville"].present?
      errors.add(:data, "Chan obligatwa ki manke: #{missing.join(', ')} (Section III)") if missing.any?

      if ident["nif"].present? && !ident["nif"].match?(/\A(\d{3}-\d{3}-\d{3}|NIF-HT-\d{9})\z/)
        errors.add(:data, "NIF dwe nan foma XXX-XXX-XXX oswa NIF-HT-XXXXXXXXX")
      end

      if ident["code_secteur"].present? && !SECTEUR_ACTIVITE.key?(ident["code_secteur"].upcase)
        errors.add(:data, "Kod sekte aktivite pa valid")
      end

      # Section IV
      errors.add(:data, "Pati fiks obligatwa (Liy 1, Section IV)") if calcul["partie_fixe"].blank?

      %w[partie_fixe chiffre_affaires masse_salariale impot_deja_paye exoneration cip interets_retard amende total].each do |field|
        val = calcul[field]
        next if val.blank?
        errors.add(:data, "#{field} dwe yon nimewo valid") unless val.to_s.match?(/\A-?\d+(\.\d+)?\z/)
      end
    end

    # ================================================================
    # Tax Calculation Engine
    # ================================================================
    def calculate_patente_tax(partie_fixe:, chiffre_affaires:, masse_salariale:, impot_deja_paye: 0, exoneration: 0, cip: 0, interets_retard: 0, amende: 0)
      pf  = partie_fixe.to_f
      ca  = chiffre_affaires.to_f
      ms  = masse_salariale.to_f
      idp = impot_deja_paye.to_f
      exo = exoneration.to_f
      cp  = cip.to_f
      ir  = interets_retard.to_f
      am  = amende.to_f

      difference         = [ ca - ms, 0 ].max
      impot_variable     = (difference * TAUX_PARTIE_VARIABLE).round(2)
      montant_calcule    = pf + impot_variable
      impot_a_payer      = [ montant_calcule - idp, 0 ].max
      montant_apres_exo  = [ impot_a_payer - exo, 0 ].max
      dsav               = (montant_apres_exo * TAUX_DSAV).round(2)
      montant_a_payer    = montant_apres_exo + dsav + cp
      total              = montant_a_payer + ir + am

      {
        "partie_fixe"                => pf.round(2),
        "chiffre_affaires"           => ca.round(2),
        "masse_salariale"            => ms.round(2),
        "difference_partie_variable" => difference.round(2),
        "impot_partie_variable"      => impot_variable,
        "montant_impot_calcule"      => montant_calcule.round(2),
        "impot_deja_paye"            => idp.round(2),
        "impot_a_payer"              => impot_a_payer.round(2),
        "exoneration"                => exo.round(2),
        "montant_impot_a_payer"      => montant_apres_exo.round(2),
        "dsav"                       => dsav,
        "cip"                        => cp.round(2),
        "montant_a_payer"            => montant_a_payer.round(2),
        "interets_retard"            => ir.round(2),
        "amende"                     => am.round(2),
        "total"                      => total.round(2)
      }
    end

    # ================================================================
    # Accessors
    # ================================================================

    # Declaration Number
    def patente_declaration_number = data["declaration_number"]

    # Periode
    def patente_annee_fiscale    = data.dig("periode", "annee_fiscale")
    def patente_mois_depot       = data.dig("periode", "mois_depot")&.to_i
    def patente_type_declaration = data.dig("periode", "type_declaration")

    # Identification
    def patente_raison_sociale   = data.dig("identification", "raison_sociale")
    def patente_nif              = data.dig("identification", "nif")
    def patente_adresse          = data.dig("identification", "adresse")
    def patente_ville            = data.dig("identification", "ville")
    def patente_telephone        = data.dig("identification", "telephone")
    def patente_email            = data.dig("identification", "email")
    def patente_code_secteur     = data.dig("identification", "code_secteur")
    def patente_nom_secteur      = data.dig("identification", "nom_secteur")

    def patente_secteur_label
      SECTEUR_ACTIVITE[patente_code_secteur&.upcase] || patente_nom_secteur || "---"
    end

    # Calcul (15 lines)
    def patente_partie_fixe               = data.dig("calcul_taxe", "partie_fixe").to_f
    def patente_chiffre_affaires          = data.dig("calcul_taxe", "chiffre_affaires").to_f
    def patente_masse_salariale           = data.dig("calcul_taxe", "masse_salariale").to_f
    def patente_difference_variable       = data.dig("calcul_taxe", "difference_partie_variable").to_f
    def patente_impot_variable            = data.dig("calcul_taxe", "impot_partie_variable").to_f
    def patente_montant_calcule           = data.dig("calcul_taxe", "montant_impot_calcule").to_f
    def patente_impot_deja_paye           = data.dig("calcul_taxe", "impot_deja_paye").to_f
    def patente_impot_a_payer             = data.dig("calcul_taxe", "impot_a_payer").to_f
    def patente_exoneration               = data.dig("calcul_taxe", "exoneration").to_f
    def patente_montant_impot_a_payer     = data.dig("calcul_taxe", "montant_impot_a_payer").to_f
    def patente_dsav                      = data.dig("calcul_taxe", "dsav").to_f
    def patente_cip                       = data.dig("calcul_taxe", "cip").to_f
    def patente_montant_a_payer           = data.dig("calcul_taxe", "montant_a_payer").to_f
    def patente_interets_retard           = data.dig("calcul_taxe", "interets_retard").to_f
    def patente_amende                    = data.dig("calcul_taxe", "amende").to_f
    def patente_total                     = data.dig("calcul_taxe", "total").to_f

    # Paiement
    def patente_methode_paiement  = data.dig("paiement", "methode")
    def patente_numero_cheque     = data.dig("paiement", "numero_cheque")
    def patente_banque            = data.dig("paiement", "banque")

    # Signature
    def patente_declarant_nom     = data.dig("signature", "nom_prenom")
    def patente_declarant_nif     = data.dig("signature", "nif_declarant")
    def patente_date_presentation = data.dig("signature", "date_presentation")

    # Display
    def patente_summary
      "Patant #{patente_annee_fiscale} - #{patente_raison_sociale} - #{patente_total.round(2)} HTG"
    end

    # Line descriptions matching DGI-F008 Section IV exactly (15 lines)
    CALCUL_LINES = {
      1  => { key: "partie_fixe",                label: "Pati Fiks (Total kolon 3, veso)",                           editable: true },
      2  => { key: "chiffre_affaires",           label: "Chif Afe (denye egzesis) (Total kolon 4, veso)",            editable: true },
      3  => { key: "masse_salariale",            label: "Mas Salaryal (denye egzesis) Art. 8 Patant (Total kolon 5, veso)", editable: true },
      4  => { key: "difference_partie_variable", label: "Diferans pati varyab (Liy 2 - Liy 3)",                      editable: false },
      5  => { key: "impot_partie_variable",      label: "Enpo pati varyab (Liy 4 × 4/1000)",                         editable: false, rate: "4/1000" },
      6  => { key: "montant_impot_calcule",      label: "Montan enpo kalkile (Liy 1 + Liy 5)",                       editable: false },
      7  => { key: "impot_deja_paye",            label: "Enpo deja peye",                                             editable: true },
      8  => { key: "impot_a_payer",              label: "Enpo pou peye (Liy 6 - Liy 7)",                             editable: false },
      9  => { key: "exoneration",                label: "Egzonerasyon",                                                editable: true },
      10 => { key: "montant_impot_a_payer",      label: "Montan enpo pou peye (Liy 8)",                               editable: false },
      11 => { key: "dsav",                       label: "DSAV (Liy 10 × 2/1000)",                                     editable: false, rate: "2/1000" },
      12 => { key: "cip",                        label: "CIP",                                                         editable: true },
      13 => { key: "nouvelle_adresse",           label: "Nouvo adrès",                                                 editable: true, admin: true },
      14 => { key: "nouveau_telephone",          label: "Nouvo nimewo telefòn",                                        editable: true, admin: true },
      15 => { key: "nouvelle_email",             label: "Nouvo adrès imel / Mesajri",                                  editable: true, admin: true }
    }.freeze

    # Section VI: Cadre reserve a l'administration
    ADMIN_LINES = {
      montant_a_payer:  "Montan pou Peye",
      interets_retard:  "Entere Reta",
      amende:           "Amand",
      total:            "TOTAL"
    }.freeze

    # Fields auto-populated from BonID citizen record
    # When cashier scans BonID, these fields pre-fill from the citizen's profile
    BONID_AUTO_FIELDS = %w[
      identification.adresse
      identification.ville
      identification.telephone
      identification.email
    ].freeze
  end
end
